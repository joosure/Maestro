defmodule SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Registry do
  @moduledoc """
  Process-local registry of known issue/change-proposal targets.

  The registry is intentionally in memory. It gives runtime-targeted producers a
  bounded set to inspect without broad tracker or repo-provider scans. Durable
  replay, cross-node ownership, and external queues remain deployment-level
  extensions.
  """

  use GenServer

  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget
  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Fields

  @default_max_targets 10_000

  defmodule State do
    @moduledoc false

    defstruct targets: %{},
              max_targets: nil,
              target_ttl_ms: nil
  end

  @type register_result :: {:ok, KnownTarget.t()} | {:error, term()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} ->
        GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))

      {:ok, name} ->
        GenServer.start_link(__MODULE__, opts, name: name)

      :error ->
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @spec register(map(), keyword()) :: register_result()
  def register(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, {:error, :known_target_registry_unavailable}, fn ->
      GenServer.call(server, {:register, attrs, opts})
    end)
  end

  @spec update_observation(String.t(), map(), keyword()) :: register_result()
  def update_observation(issue_id, attrs, opts \\ [])
      when is_binary(issue_id) and is_map(attrs) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, {:error, :known_target_registry_unavailable}, fn ->
      GenServer.call(server, {:update_observation, issue_id, attrs, opts})
    end)
  end

  @spec mark_enqueued(String.t(), keyword()) :: register_result()
  def mark_enqueued(issue_id, opts \\ []) when is_binary(issue_id) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, {:error, :known_target_registry_unavailable}, fn ->
      GenServer.call(server, {:mark_enqueued, issue_id, opts})
    end)
  end

  @spec list_targets(keyword()) :: [KnownTarget.t()]
  def list_targets(opts \\ []) when is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)
    limit = Keyword.get(opts, :limit)

    with_server(server, [], fn ->
      GenServer.call(server, {:list_targets, limit, opts})
    end)
  end

  @spec get(String.t(), keyword()) :: KnownTarget.t() | nil
  def get(issue_id, opts \\ []) when is_binary(issue_id) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, nil, fn ->
      GenServer.call(server, {:get, issue_id, opts})
    end)
  end

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) when is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, :ok, fn ->
      GenServer.call(server, :reset)
    end)
  end

  @impl true
  def init(opts) do
    {:ok,
     %State{
       max_targets: positive_integer(Keyword.get(opts, :max_targets), @default_max_targets),
       target_ttl_ms: non_negative_integer_or_nil(Keyword.get(opts, :target_ttl_ms))
     }}
  end

  @impl true
  def handle_call({:register, attrs, opts}, _from, %State{} = state) do
    state = prune_expired(state, opts)

    case KnownTarget.new(attrs, opts) do
      {:ok, %KnownTarget{} = target} ->
        target = merge_existing(state, target, opts)
        state = state |> put_target(target) |> enforce_target_limit()
        {:reply, {:ok, target}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:update_observation, issue_id, attrs, opts}, _from, %State{} = state) do
    state = prune_expired(state, opts)

    case Map.get(state.targets, issue_id) do
      %KnownTarget{} = existing ->
        attrs =
          attrs
          |> Map.put(Fields.issue_id(), issue_id)
          |> Map.put_new(Fields.tracker_kind(), existing.tracker_kind)
          |> Map.put_new(Fields.repo_provider_kind(), existing.repo_provider_kind)
          |> Map.put_new(Fields.repository(), existing.repository)

        case KnownTarget.new(attrs, opts) do
          {:ok, %KnownTarget{} = incoming} ->
            target = KnownTarget.merge(existing, incoming, opts)
            state = put_target(state, target)
            {:reply, {:ok, target}, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end

      nil ->
        {:reply, {:error, {:known_target_not_found, issue_id}}, state}
    end
  end

  def handle_call({:mark_enqueued, issue_id, opts}, _from, %State{} = state) do
    state = prune_expired(state, opts)

    case Map.get(state.targets, issue_id) do
      %KnownTarget{} = existing ->
        now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)
        target = %{existing | last_enqueued_at_ms: now_ms, updated_at_ms: now_ms}
        state = put_target(state, target)
        {:reply, {:ok, target}, state}

      nil ->
        {:reply, {:error, {:known_target_not_found, issue_id}}, state}
    end
  end

  def handle_call({:list_targets, limit, opts}, _from, %State{} = state) do
    state = prune_expired(state, opts)

    targets =
      state.targets
      |> Map.values()
      |> Enum.sort_by(& &1.updated_at_ms, :desc)
      |> maybe_take(limit)

    {:reply, targets, state}
  end

  def handle_call({:get, issue_id, opts}, _from, %State{} = state) do
    state = prune_expired(state, opts)
    {:reply, Map.get(state.targets, issue_id), state}
  end

  def handle_call(:reset, _from, %State{} = state) do
    {:reply, :ok, %{state | targets: %{}}}
  end

  defp merge_existing(%State{} = state, %KnownTarget{issue_id: issue_id} = target, opts) do
    case Map.get(state.targets, issue_id) do
      %KnownTarget{} = existing -> KnownTarget.merge(existing, target, opts)
      nil -> target
    end
  end

  defp put_target(%State{} = state, %KnownTarget{issue_id: issue_id} = target) do
    %{state | targets: Map.put(state.targets, issue_id, target)}
  end

  defp prune_expired(%State{target_ttl_ms: nil} = state, _opts), do: state

  defp prune_expired(%State{target_ttl_ms: ttl_ms} = state, opts) when is_integer(ttl_ms) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)

    targets =
      Map.reject(state.targets, fn {_issue_id, %KnownTarget{} = target} ->
        target_age_ms(target, now_ms) >= ttl_ms
      end)

    %{state | targets: targets}
  end

  defp enforce_target_limit(%State{max_targets: max_targets} = state) when map_size(state.targets) <= max_targets,
    do: state

  defp enforce_target_limit(%State{max_targets: max_targets} = state) do
    overflow_count = map_size(state.targets) - max_targets

    evicted_issue_ids =
      state.targets
      |> Map.values()
      |> Enum.sort_by(&target_sort_ms/1, :asc)
      |> Enum.take(overflow_count)
      |> Enum.map(& &1.issue_id)

    %{state | targets: Map.drop(state.targets, evicted_issue_ids)}
  end

  defp target_age_ms(%KnownTarget{} = target, now_ms) when is_integer(now_ms) do
    last_seen_ms = target.updated_at_ms || target.registered_at_ms || now_ms
    now_ms - last_seen_ms
  end

  defp target_sort_ms(%KnownTarget{} = target), do: target.updated_at_ms || target.registered_at_ms || 0

  defp maybe_take(targets, limit) when is_integer(limit) and limit >= 0, do: Enum.take(targets, limit)
  defp maybe_take(targets, _limit), do: targets

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer_or_nil(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer_or_nil(_value), do: nil

  defp with_server(server, fallback, fun) when is_atom(server) and is_function(fun, 0) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> fun.()
      _other -> fallback
    end
  end

  defp with_server(server, _fallback, fun) when is_pid(server) and is_function(fun, 0), do: fun.()
  defp with_server(_server, fallback, _fun), do: fallback
end
