defmodule SymphonyElixir.ChangeProposalReconciliation do
  @moduledoc """
  Coordinates tracker issue state with repository change-proposal readiness.

  This context owns the cross-boundary use case:

    * discover the issue's attached change proposal through the tracker facade
    * inspect provider-specific review/check/mergeability state through the repo-provider facade
    * apply workflow policy to decide whether the tracker issue should move routes
    * delegate route resolution, transition confirmation, counters, and events
      to focused modules under this context

  Orchestrator code should call this facade as a poll-cycle capability instead of
  binding directly to tracker or repo-provider reconciliation details.
  """

  alias SymphonyElixir.ChangeProposalReconciliation.{
    CandidateInbox,
    Contract,
    KnownTarget,
    Producer,
    Reconciler
  }

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @spec reconcile(map(), map(), keyword()) :: map()
  defdelegate reconcile(settings, runtime_state, opts \\ []), to: Reconciler

  @spec enqueue_issue_ids([term()], keyword()) ::
          {:ok, CandidateInbox.enqueue_result()} | {:error, term()}
  def enqueue_issue_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts) do
    CandidateInbox.enqueue_issue_ids(issue_ids, opts)
  end

  @spec register_known_target(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def register_known_target(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)
    registry = Keyword.get(opts, :registry, KnownTarget.Registry)
    inbox = Keyword.get(opts, :inbox, CandidateInbox)
    registry_opts = opts |> Keyword.put(:server, registry) |> Keyword.put(:now_ms, now_ms)
    inbox_opts = Keyword.put(opts, :server, inbox)

    with {:ok, target} <- KnownTarget.Registry.register(attrs, registry_opts),
         {:ok, enqueue_result} <- CandidateInbox.enqueue_issue_ids([target.issue_id], inbox_opts),
         :ok <- emit_candidate_enqueue_dropped(target, enqueue_result, opts),
         {:ok, target} <- maybe_mark_enqueued(target, enqueue_result, registry_opts) do
      {:ok, %{target: target, enqueue: enqueue_result}}
    end
  end

  @spec known_targets(keyword()) :: [SymphonyElixir.ChangeProposalReconciliation.KnownTarget.t()]
  def known_targets(opts \\ []) when is_list(opts) do
    KnownTarget.Registry.list_targets(opts)
  end

  @spec reset_known_targets(keyword()) :: :ok
  def reset_known_targets(opts \\ []) when is_list(opts) do
    KnownTarget.Registry.reset(opts)
  end

  @spec record_tracker_tool_result(map(), String.t() | nil, term(), term(), keyword()) :: :ok
  def record_tracker_tool_result(tracker, tool, arguments, result, opts \\ []) do
    Producer.TrackerToolResultHandler.record_tracker_tool_result(
      tracker,
      tool,
      arguments,
      result,
      opts
    )
  end

  @spec run_known_target_watcher_once(keyword()) :: Producer.Watcher.run_result()
  def run_known_target_watcher_once(opts \\ []) when is_list(opts) do
    Producer.Watcher.run_once(opts)
  end

  defp maybe_mark_enqueued(target, enqueue_result, registry_opts) when is_map(enqueue_result) do
    if Map.get(enqueue_result, :accepted_count, 0) + Map.get(enqueue_result, :duplicate_count, 0) > 0 do
      KnownTarget.Registry.mark_enqueued(target.issue_id, registry_opts)
    else
      {:ok, target}
    end
  end

  defp emit_candidate_enqueue_dropped(target, %{dropped_count: dropped_count} = enqueue_result, opts)
       when is_integer(dropped_count) and dropped_count > 0 do
    event_fields =
      enqueue_result
      |> Map.merge(%{
        component: Contract.component(),
        producer: Contract.producer(:known_target_registry),
        issue_id: target.issue_id,
        tracker_kind: target.tracker_kind,
        repo_provider_kind: target.repo_provider_kind,
        repository: target.repository,
        change_proposal_number: target.number,
        change_proposal_url: target.url
      })

    opts
    |> Keyword.get(:emit_event_fn, &ObservabilityLogger.emit/3)
    |> then(& &1.(:warning, Contract.event(:candidate_enqueue_dropped), event_fields))

    :ok
  end

  defp emit_candidate_enqueue_dropped(_target, _enqueue_result, _opts), do: :ok
end
