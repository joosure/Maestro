defmodule SymphonyWorkerDaemon.CapacityManager do
  @moduledoc false

  use GenServer

  alias SymphonyWorkerDaemon.CapacityManager.{Leases, Options, Status}

  @default_max_sessions 1

  @type status :: :ready | :full | :draining | :unavailable
  @type lease_id :: String.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec admit(map()) :: {:ok, lease_id()} | {:error, :worker_full | :tenant_session_quota_exceeded | :draining | :unavailable}
  def admit(attrs) when is_map(attrs), do: admit(__MODULE__, attrs)

  @spec admit(GenServer.server(), map()) :: {:ok, lease_id()} | {:error, :worker_full | :tenant_session_quota_exceeded | :draining | :unavailable}
  def admit(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:admit, attrs})
  end

  @spec release(lease_id() | nil) :: :ok
  def release(lease_id), do: release(__MODULE__, lease_id)

  @spec release(GenServer.server(), lease_id() | nil) :: :ok
  def release(_server, nil), do: :ok
  def release(server, lease_id) when is_binary(lease_id), do: GenServer.call(server, {:release, lease_id})

  @spec status() :: map()
  def status, do: status(__MODULE__)

  @spec status(GenServer.server()) :: map()
  def status(server), do: GenServer.call(server, :status)

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) when is_list(opts) do
    max_sessions = Options.positive_integer(Keyword.get(opts, :max_sessions), @default_max_sessions)

    {:ok,
     %{
       max_sessions: max_sessions,
       max_sessions_per_tenant: Options.optional_positive_integer(Keyword.get(opts, :max_sessions_per_tenant)),
       leases: %{},
       draining?: Keyword.get(opts, :draining?, false),
       unavailable?: Keyword.get(opts, :unavailable?, false)
     }}
  end

  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:admit, attrs}, _from, %{unavailable?: true} = state) do
    {:reply, {:error, :unavailable}, state_with_last_request(state, attrs)}
  end

  def handle_call({:admit, attrs}, _from, %{draining?: true} = state) do
    {:reply, {:error, :draining}, state_with_last_request(state, attrs)}
  end

  def handle_call({:admit, attrs}, _from, state) do
    cond do
      map_size(state.leases) >= state.max_sessions ->
        {:reply, {:error, :worker_full}, state_with_last_request(state, attrs)}

      Leases.tenant_quota_exceeded?(state.leases, state.max_sessions_per_tenant, attrs) ->
        {:reply, {:error, :tenant_session_quota_exceeded}, state_with_last_request(state, attrs)}

      true ->
        lease_id = Ecto.UUID.generate()
        leases = Leases.add(state.leases, lease_id, attrs, System.monotonic_time(:millisecond))
        {:reply, {:ok, lease_id}, %{state | leases: leases}}
    end
  end

  def handle_call({:release, lease_id}, _from, state) do
    {:reply, :ok, %{state | leases: Map.delete(state.leases, lease_id)}}
  end

  def handle_call(:status, _from, state) do
    {:reply, Status.payload(state), state}
  end

  defp state_with_last_request(state, attrs), do: Map.put(state, :last_rejected_request, attrs)
end
