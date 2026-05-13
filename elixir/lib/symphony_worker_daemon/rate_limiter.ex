defmodule SymphonyWorkerDaemon.RateLimiter do
  @moduledoc false

  use GenServer

  alias SymphonyWorkerDaemon.RateLimiter.{Bucket, Options, Pruning}

  @default_window_ms 60_000
  @default_max_buckets 100_000

  @type scope :: atom()
  @type decision :: :ok | {:error, {:rate_limited, pos_integer(), pos_integer(), pos_integer()}}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :id, Keyword.get(opts, :name, __MODULE__)),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec check(GenServer.server() | nil, scope(), term(), keyword()) :: decision()
  def check(server, scope, key, opts \\ [])

  def check(nil, _scope, _key, _opts), do: :ok

  def check(server, scope, key, opts) when is_atom(scope) and is_list(opts) do
    case Options.limit(opts) do
      :infinity ->
        :ok

      limit ->
        GenServer.call(server, {:check, scope, Bucket.normalized_key(key), limit, Options.window_ms(opts)})
    end
  catch
    :exit, _reason -> {:error, {:rate_limited, @default_window_ms, 1, @default_window_ms}}
  end

  @spec status(GenServer.server() | nil) :: map()
  def status(nil), do: %{status: :disabled}

  def status(server) do
    GenServer.call(server, :status)
  catch
    :exit, _reason -> %{status: :unavailable}
  end

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) when is_list(opts) do
    {:ok,
     %{
       buckets: %{},
       max_buckets: Options.positive_integer(Keyword.get(opts, :max_buckets), @default_max_buckets),
       last_pruned_at_ms: now_ms()
     }}
  end

  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:check, scope, key, limit, window_ms}, _from, state) do
    now_ms = now_ms()
    state = Pruning.maybe_prune(state, now_ms, @default_window_ms)
    bucket_key = {scope, key}
    bucket = Bucket.current(Map.get(state.buckets, bucket_key), now_ms, window_ms)

    if bucket.count < limit do
      buckets = Map.put(state.buckets, bucket_key, %{bucket | count: bucket.count + 1})
      {:reply, :ok, %{state | buckets: buckets}}
    else
      retry_after_ms = max(bucket.window_started_at_ms + window_ms - now_ms, 1)
      {:reply, {:error, {:rate_limited, retry_after_ms, limit, window_ms}}, state}
    end
  end

  def handle_call(:status, _from, state) do
    {:reply, %{status: :ready, bucket_count: map_size(state.buckets), max_buckets: state.max_buckets}, state}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
