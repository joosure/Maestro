defmodule SymphonyElixir.Orchestrator.ServerOptions do
  @moduledoc false

  @worker_exit_issue_refresh_timeout_ms 2_000
  @worker_exit_issue_fact_freshness_ms 10_000

  alias SymphonyElixir.Agent.Runner.ActiveSessions
  alias SymphonyElixir.ChangeProposalReconciliation.CandidateInbox
  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.StatusDashboard
  alias SymphonyElixir.Orchestrator.Events
  alias SymphonyElixir.Orchestrator.IssueDispatch
  alias SymphonyElixir.Orchestrator.Retry
  alias SymphonyElixir.Orchestrator.RunningState
  alias SymphonyElixir.Orchestrator.Runtime
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workspace

  @spec poll_cycle_opts() :: keyword()
  def poll_cycle_opts do
    [
      running_opts: &running_opts/1,
      change_proposal_reconciler_opts: &change_proposal_reconciler_opts/0,
      notify_dashboard: &notify_dashboard/0
    ]
  end

  @spec agent_update_opts() :: keyword()
  def agent_update_opts do
    [
      notify_dashboard: &notify_dashboard/0
    ]
  end

  @spec retry_issue_opts(State.t(), map()) :: keyword()
  def retry_issue_opts(%State{} = state, metadata) when is_map(metadata) do
    [
      fetch_candidate_issues: &Tracker.fetch_candidate_issues/0,
      dispatch_context: Runtime.dispatch_context(),
      dispatch_runtime: Runtime.dispatch_runtime(state, metadata[:worker_host]),
      dispatch_issue: &IssueDispatch.dispatch_issue/4,
      release_issue_claim: &release_issue_claim/2,
      cleanup_issue_workspace: &cleanup_issue_workspace/3,
      emit_event: &Events.emit/5
    ]
  end

  @spec retry_message_opts() :: keyword()
  def retry_message_opts do
    [
      emit_event: &Events.emit/5,
      retry_issue_opts: &retry_issue_opts/2,
      notify_dashboard: &notify_dashboard/0
    ]
  end

  @spec worker_exit_opts() :: keyword()
  def worker_exit_opts do
    [
      fetch_issue_states_by_ids: &Tracker.fetch_issue_states_by_ids/1,
      issue_refresh_timeout_ms: @worker_exit_issue_refresh_timeout_ms,
      issue_fact_freshness_ms: @worker_exit_issue_fact_freshness_ms,
      notify_dashboard: &notify_dashboard/0
    ]
  end

  @spec running_opts(State.t() | map() | nil) :: keyword()
  def running_opts(state) do
    emit_event = &Events.emit/5
    config = Config.settings!()
    poll_interval_ms = Runtime.running_poll_interval_ms(state, config.polling.interval_ms)
    read_timeout_ms = Runtime.agent_provider_timeout_option("read_timeout_ms", 5_000)
    completion_grace_ms = max(poll_interval_ms, read_timeout_ms * 2)

    [
      emit_event: emit_event,
      emit_issue_reconcile_event: &Events.emit_issue_reconcile/5,
      cleanup_issue_workspace: &cleanup_issue_workspace/3,
      cleanup_active_agent_session: &ActiveSessions.cleanup_owner/2,
      record_session_completion_totals: &RunningState.record_session_completion/2,
      completion_grace_ms: completion_grace_ms,
      schedule_retry: fn state, issue_id, attempt, metadata ->
        Retry.schedule(state, issue_id, attempt, metadata, emit_event: emit_event)
      end
    ]
  end

  @spec terminal_cleanup_opts() :: keyword()
  def terminal_cleanup_opts do
    [
      fetch_terminal_issues: fn -> Tracker.fetch_terminal_issues() end,
      cleanup_workspace: &cleanup_issue_workspace/1,
      emit_event: fn level, event, extra_fields ->
        Events.emit(level, event, nil, nil, extra_fields)
      end
    ]
  end

  @spec change_proposal_reconciler_opts() :: keyword()
  def change_proposal_reconciler_opts do
    [
      targeted_issue_ids_fn: &CandidateInbox.drain_issue_ids/1,
      defer_targeted_issue_ids_fn: &CandidateInbox.defer_issue_ids/2
    ]
  end

  @spec notify_dashboard() :: term()
  def notify_dashboard do
    StatusDashboard.notify_update()
  end

  @spec release_issue_claim(State.t(), String.t()) :: State.t()
  def release_issue_claim(%State{} = state, issue_id) do
    %{state | claimed: MapSet.delete(state.claimed, issue_id)}
  end

  @spec cleanup_issue_workspace(String.t()) :: :ok | {:error, term()}
  def cleanup_issue_workspace(identifier), do: cleanup_issue_workspace(identifier, nil, nil)

  @spec cleanup_issue_workspace(String.t(), String.t() | nil, String.t() | nil) :: :ok | {:error, term()}
  def cleanup_issue_workspace(identifier, worker_host, workspace_path) when is_binary(identifier) do
    Events.emit(
      :info,
      :issue_workspace_cleanup_requested,
      nil,
      nil,
      %{
        issue_identifier: identifier,
        worker_host: worker_host,
        workspace_path: workspace_path,
        policy_action: "cleanup_workspace"
      }
    )

    Workspace.remove_issue_workspaces(identifier, worker_host, workspace_path)
  end

  def cleanup_issue_workspace(_identifier, _worker_host, _workspace_path), do: :ok
end
