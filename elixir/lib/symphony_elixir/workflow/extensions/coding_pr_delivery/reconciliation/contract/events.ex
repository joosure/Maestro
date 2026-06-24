defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Events do
  @moduledoc false

  @tracker_tool_result_ignored_event :change_proposal_tracker_tool_result_ignored
  @candidate_enqueue_dropped_event :change_proposal_candidate_enqueue_dropped
  @candidate_suspended_event :change_proposal_candidate_suspended
  @known_target_watcher_failed_event :change_proposal_known_target_watcher_failed
  @startup_backlog_bootstrap_completed_event :change_proposal_startup_backlog_bootstrap_completed

  @config_invalid_event :change_proposal_reconciliation_config_invalid
  @reconciliation_started_event :change_proposal_reconciliation_started
  @reconciliation_completed_event :change_proposal_reconciliation_completed
  @candidate_selected_event :change_proposal_reconciliation_candidate_selected
  @candidate_skipped_event :change_proposal_reconciliation_candidate_skipped
  @change_proposal_located_event :change_proposal_located
  @change_proposal_lookup_failed_event :change_proposal_lookup_failed
  @decision_event :change_proposal_reconciliation_decision
  @transition_attempted_event :change_proposal_transition_attempted
  @transition_failed_event :change_proposal_transition_failed
  @transition_skipped_event :change_proposal_transition_skipped
  @transition_succeeded_event :change_proposal_transition_succeeded

  @transition_events [
    Atom.to_string(@transition_attempted_event),
    Atom.to_string(@transition_failed_event),
    Atom.to_string(@transition_skipped_event),
    Atom.to_string(@transition_succeeded_event)
  ]

  @type event_id ::
          :tracker_tool_result_ignored
          | :candidate_enqueue_dropped
          | :candidate_suspended
          | :known_target_watcher_failed
          | :startup_backlog_bootstrap_completed
          | :config_invalid
          | :reconciliation_started
          | :reconciliation_completed
          | :candidate_selected
          | :candidate_skipped
          | :change_proposal_located
          | :change_proposal_lookup_failed
          | :decision
          | :transition_attempted
          | :transition_failed
          | :transition_skipped
          | :transition_succeeded

  @spec event(event_id()) :: atom()
  def event(:tracker_tool_result_ignored), do: @tracker_tool_result_ignored_event
  def event(:candidate_enqueue_dropped), do: @candidate_enqueue_dropped_event
  def event(:candidate_suspended), do: @candidate_suspended_event
  def event(:known_target_watcher_failed), do: @known_target_watcher_failed_event
  def event(:startup_backlog_bootstrap_completed), do: @startup_backlog_bootstrap_completed_event
  def event(:config_invalid), do: @config_invalid_event
  def event(:reconciliation_started), do: @reconciliation_started_event
  def event(:reconciliation_completed), do: @reconciliation_completed_event
  def event(:candidate_selected), do: @candidate_selected_event
  def event(:candidate_skipped), do: @candidate_skipped_event
  def event(:change_proposal_located), do: @change_proposal_located_event
  def event(:change_proposal_lookup_failed), do: @change_proposal_lookup_failed_event
  def event(:decision), do: @decision_event
  def event(:transition_attempted), do: @transition_attempted_event
  def event(:transition_failed), do: @transition_failed_event
  def event(:transition_skipped), do: @transition_skipped_event
  def event(:transition_succeeded), do: @transition_succeeded_event

  @spec event_name(event_id()) :: String.t()
  def event_name(event_id), do: event_id |> event() |> Atom.to_string()

  @spec transition_events() :: [String.t()]
  def transition_events, do: @transition_events

  @spec transition_event_name(:attempted | :failed | :skipped | :succeeded) :: String.t()
  def transition_event_name(:attempted), do: event_name(:transition_attempted)
  def transition_event_name(:failed), do: event_name(:transition_failed)
  def transition_event_name(:skipped), do: event_name(:transition_skipped)
  def transition_event_name(:succeeded), do: event_name(:transition_succeeded)
end
