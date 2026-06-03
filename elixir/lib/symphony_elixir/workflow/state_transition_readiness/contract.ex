defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Contract do
  @moduledoc """
  Compatibility facade for state-transition readiness contract identifiers.

  New code can depend on the narrower contract modules under this namespace when
  it needs only envelope, evidence, result, or enum-like value identifiers.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Evidence
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Result
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  defdelegate schema_key(), to: Envelope
  defdelegate policy_id_key(), to: Envelope
  defdelegate observations_key(), to: Envelope
  defdelegate declarations_key(), to: Envelope
  defdelegate metadata_key(), to: Envelope

  defdelegate workpad_key(), to: Evidence
  defdelegate repo_key(), to: Evidence
  defdelegate change_proposal_key(), to: Evidence
  defdelegate validation_key(), to: Evidence
  defdelegate checks_key(), to: Evidence
  defdelegate feedback_key(), to: Evidence
  defdelegate status_key(), to: Evidence
  defdelegate source_key(), to: Evidence
  defdelegate key_key(), to: Evidence
  defdelegate id_key(), to: Evidence
  defdelegate url_key(), to: Evidence
  defdelegate head_ref_key(), to: Evidence
  defdelegate head_sha_key(), to: Evidence
  defdelegate published_head_sha_key(), to: Evidence
  defdelegate commits_key(), to: Evidence
  defdelegate change_kind_key(), to: Evidence
  defdelegate no_code_change_justification_key(), to: Evidence
  defdelegate linked_to_tracker_key(), to: Evidence
  defdelegate observed_at_key(), to: Evidence
  defdelegate commands_key(), to: Evidence
  defdelegate workpad_id_key(), to: Evidence
  defdelegate updated_at_key(), to: Evidence
  defdelegate provider_kind_key(), to: Evidence
  defdelegate repository_key(), to: Evidence
  defdelegate number_key(), to: Evidence
  defdelegate summary_key(), to: Evidence
  defdelegate actionable_count_key(), to: Evidence
  defdelegate working_tree_clean_key(), to: Evidence
  defdelegate pushed_key(), to: Evidence
  defdelegate command_key(), to: Evidence
  defdelegate cwd_key(), to: Evidence
  defdelegate exit_code_key(), to: Evidence

  defdelegate target_state_key(), to: Result
  defdelegate capability_gaps_key(), to: Result
  defdelegate downgrades_key(), to: Result
  defdelegate error_code_key(), to: Result
  defdelegate reason_code_key(), to: Result
  defdelegate reason_codes_key(), to: Result
  defdelegate code_key(), to: Result
  defdelegate detail_key(), to: Result

  defdelegate passed_status(), to: Values
  defdelegate blocked_status(), to: Values
  defdelegate missing_status(), to: Values
  defdelegate failed_status(), to: Values
  defdelegate stale_status(), to: Values
  defdelegate complete_status(), to: Values
  defdelegate incomplete_status(), to: Values
  defdelegate unknown_status(), to: Values
  defdelegate unavailable_status(), to: Values
  defdelegate not_required_status(), to: Values
  defdelegate pending_status(), to: Values
  defdelegate linked_status(), to: Values
  defdelegate created_status(), to: Values
  defdelegate updated_status(), to: Values
  defdelegate clear_status(), to: Values
  defdelegate action_required_status(), to: Values
  defdelegate code_change_kind(), to: Values
  defdelegate no_code_change_kind(), to: Values
  defdelegate typed_tool_observed_source(), to: Values
  defdelegate tracker_observed_source(), to: Values
  defdelegate repo_observed_source(), to: Values
  defdelegate repo_provider_observed_source(), to: Values
end
