defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.{Client, Endpoint, EndpointState}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver.{Candidates, Selection}
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @type candidate :: %{
          required(:endpoint) => String.t(),
          optional(:worker_id) => String.t(),
          optional(:endpoint_id) => String.t(),
          optional(:source) => String.t()
        }

  @type selection :: %{
          required(:endpoint) => String.t(),
          optional(:worker_id) => String.t(),
          optional(:daemon_instance_id) => String.t(),
          optional(:endpoint_id) => String.t(),
          optional(:source) => String.t(),
          optional(:health) => map()
        }

  @spec resolve(Target.t(), keyword()) :: {:ok, selection()} | {:error, term()}
  def resolve(target, opts \\ [])

  def resolve(%Target{placement: :worker_daemon} = target, opts) when is_list(opts) do
    candidates = candidates(target, opts)

    case candidates do
      [] -> {:error, :worker_daemon_endpoint_missing}
      [_candidate | _rest] -> select_candidate(candidates, target, opts, [])
    end
  end

  def resolve(%Target{} = target, _opts), do: {:error, {:worker_daemon_pool_invalid_placement, target.placement}}

  @spec candidates(Target.t(), keyword()) :: [candidate()]
  def candidates(%Target{} = target, opts \\ []) when is_list(opts) do
    Candidates.build(target, opts)
  end

  defp select_candidate([], _target, _opts, failures) do
    {:error, {:worker_daemon_pool_unavailable, Enum.reverse(failures)}}
  end

  defp select_candidate([candidate | rest], target, opts, failures) do
    candidate_target = Selection.target_for_candidate(target, candidate)
    preflight_opts = Keyword.put(opts, :worker_daemon_endpoint, candidate.endpoint)

    case candidate_health(candidate, candidate_target, preflight_opts) do
      {:ok, health, health_source} ->
        emit_pool_event(:info, :worker_daemon_pool_candidate_selected, target, candidate, %{health_source: health_source})
        {:ok, Selection.success(candidate, health, health_source)}

      {:error, reason} ->
        emit_pool_event(:debug, :worker_daemon_pool_candidate_rejected, target, candidate, %{reason: Selection.safe_reason(reason)})
        select_candidate(rest, target, opts, [Selection.failure(candidate, reason) | failures])
    end
  end

  defp candidate_health(candidate, %Target{} = target, opts) do
    case EndpointState.circuit_status(candidate.endpoint, opts) do
      {:open, details} ->
        {:error, {:worker_daemon_circuit_open, details}}

      :closed ->
        cached_or_preflight(candidate, target, opts)
    end
  end

  defp cached_or_preflight(candidate, %Target{} = target, opts) do
    case EndpointState.cached_health(candidate.endpoint, opts) do
      {:ok, health} ->
        case Client.validate_health(target, health, opts) do
          :ok -> {:ok, health, "cache"}
          {:error, reason} -> preflight_candidate(candidate, target, opts, reason)
        end

      :miss ->
        preflight_candidate(candidate, target, opts, nil)
    end
  end

  defp preflight_candidate(candidate, %Target{} = target, opts, stale_cache_reason) do
    if stale_cache_reason do
      EndpointState.record_failure(candidate.endpoint, stale_cache_reason, opts)
    end

    case Client.preflight(target, opts) do
      {:ok, health} ->
        EndpointState.record_success(candidate.endpoint, health, opts)
        {:ok, health, "preflight"}

      {:error, reason} ->
        EndpointState.record_failure(candidate.endpoint, reason, opts)
        {:error, reason}
    end
  end

  defp emit_pool_event(level, event, %Target{} = target, candidate, extra) when is_map(candidate) and is_map(extra) do
    ObsLogger.emit(
      level,
      event,
      %{
        component: "agent_runtime.worker_daemon_pool",
        worker_placement: "worker_daemon",
        worker_pool: target.worker_pool,
        workspace_path: target.workspace_path,
        worker_daemon_endpoint: safe_endpoint(Map.get(candidate, :endpoint)),
        worker_daemon_worker_id: Map.get(candidate, :worker_id),
        worker_daemon_endpoint_id: Map.get(candidate, :endpoint_id),
        worker_daemon_endpoint_source: Map.get(candidate, :source)
      }
      |> Map.merge(extra)
    )
  end

  defp safe_endpoint(value), do: Endpoint.safe(value)
end
