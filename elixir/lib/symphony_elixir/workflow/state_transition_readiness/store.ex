defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Store do
  @moduledoc """
  Process-local structured evidence store for workflow transition readiness.

  Human-readable tracker comments are presentation only. This store keeps the
  bounded observations that typed tools and backend collectors produce for
  transition validators.
  """

  use GenServer

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope

  @default_max_records 10_000
  @schema_key Envelope.schema_key()
  @policy_id_key Envelope.policy_id_key()
  @observations_key Envelope.observations_key()
  @declarations_key Envelope.declarations_key()
  @metadata_key Envelope.metadata_key()

  defmodule State do
    @moduledoc false

    defstruct records: %{},
              max_records: nil
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @spec record(term() | [term()], map(), keyword()) :: :ok
  def record(keys, evidence, opts \\ []) when is_map(evidence) and is_list(opts) do
    keys = normalize_keys(keys)
    server = Keyword.get(opts, :server, __MODULE__)

    if keys == [] do
      :ok
    else
      with_server(server, :ok, fn ->
        GenServer.call(server, {:record, keys, normalize_evidence(evidence), opts})
      end)
    end
  end

  @spec snapshot(term() | [term()], keyword()) :: map()
  def snapshot(keys, opts \\ []) when is_list(opts) do
    keys = normalize_keys(keys)
    server = Keyword.get(opts, :server, __MODULE__)

    if keys == [] do
      empty_evidence()
    else
      with_server(server, empty_evidence(), fn ->
        GenServer.call(server, {:snapshot, keys})
      end)
    end
  end

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) when is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, :ok, fn ->
      GenServer.call(server, :reset)
    end)
  end

  @spec scope_issue_keys(term(), term() | [term()]) :: [String.t()]
  def scope_issue_keys(run_id, issue_keys) do
    keys = normalize_keys(issue_keys)

    case normalize_keys(run_id) do
      [run_id] -> Enum.map(keys, &run_issue_key(run_id, &1))
      _run_id -> keys
    end
  end

  @impl true
  def init(opts) do
    {:ok, %State{max_records: positive_integer(Keyword.get(opts, :max_records), @default_max_records)}}
  end

  @impl true
  def handle_call({:record, keys, evidence, _opts}, _from, %State{} = state) do
    records =
      Enum.reduce(keys, state.records, fn key, acc ->
        current = Map.get(acc, key, empty_evidence())
        Map.put(acc, key, deep_merge(current, evidence))
      end)

    {:reply, :ok, %{state | records: enforce_limit(records, state.max_records)}}
  end

  def handle_call({:snapshot, keys}, _from, %State{} = state) do
    evidence =
      keys
      |> Enum.map(&Map.get(state.records, &1, empty_evidence()))
      |> Enum.reduce(empty_evidence(), &deep_merge/2)

    {:reply, evidence, state}
  end

  def handle_call(:reset, _from, %State{} = state) do
    {:reply, :ok, %{state | records: %{}}}
  end

  defp empty_evidence do
    %{
      @observations_key => %{},
      @declarations_key => %{},
      @metadata_key => %{}
    }
  end

  defp normalize_evidence(%{@observations_key => observations} = evidence) when is_map(observations) do
    evidence
    |> Map.take([@schema_key, @policy_id_key, @observations_key, @declarations_key, @metadata_key])
  end

  defp normalize_evidence(observations) when is_map(observations) do
    empty_evidence()
    |> Map.put(@observations_key, observations)
  end

  defp normalize_keys(keys) do
    keys
    |> List.wrap()
    |> Enum.flat_map(&normalize_key/1)
    |> Enum.uniq()
  end

  defp normalize_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      normalized -> [normalized]
    end
  end

  defp normalize_key(value) when is_integer(value), do: [Integer.to_string(value)]
  defp normalize_key(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_key()
  defp normalize_key(_value), do: []

  defp run_issue_key(run_id, issue_key) do
    "run:" <> run_id <> ":issue:" <> issue_key
  end

  defp deep_merge(%{@observations_key => left_observations} = left, %{@observations_key => right_observations} = right)
       when is_map(left_observations) and is_map(right_observations) do
    Map.merge(left, right, fn
      @observations_key, left_value, right_value when is_map(left_value) and is_map(right_value) ->
        Map.merge(left_value, right_value)

      _key, left_value, right_value when is_map(left_value) and is_map(right_value) ->
        deep_merge(left_value, right_value)

      _key, _left_value, right_value ->
        right_value
    end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp enforce_limit(records, max_records) when map_size(records) <= max_records, do: records

  defp enforce_limit(records, max_records) do
    records
    |> Enum.take(-max_records)
    |> Map.new()
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp with_server(server, default, fun) when is_atom(server) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> safe_call(default, fun)
      _pid -> default
    end
  end

  defp with_server(server, default, fun) when is_pid(server), do: safe_call(default, fun)
  defp with_server(_server, default, _fun), do: default

  defp safe_call(default, fun) do
    fun.()
  catch
    :exit, _reason -> default
  end
end
