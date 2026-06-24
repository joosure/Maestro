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

  defdelegate status_key(), to: Evidence
  defdelegate source_key(), to: Evidence
  defdelegate key_key(), to: Evidence
  defdelegate id_key(), to: Evidence
  defdelegate url_key(), to: Evidence
  defdelegate observed_at_key(), to: Evidence
  defdelegate updated_at_key(), to: Evidence
  defdelegate summary_key(), to: Evidence

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
  defdelegate typed_tool_observed_source(), to: Values
  defdelegate tracker_observed_source(), to: Values
  defdelegate repo_observed_source(), to: Values
  defdelegate repo_provider_observed_source(), to: Values
end
