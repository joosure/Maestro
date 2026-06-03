defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffContract do
  @moduledoc """
  Stable identifiers and accepted values for the review-handoff readiness policy.
  """

  alias SymphonyElixir.Workflow.Profiles.CodingPrDelivery
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract

  @name "review_handoff"
  @version "v1"
  @schema @name <> "." <> @version
  @coding_pr_delivery_policy_id CodingPrDelivery.kind() <> "." <> @schema
  @not_ready_error "review_handoff_not_ready"
  @passing_change_proposal_statuses [Contract.linked_status(), Contract.created_status(), Contract.updated_status()]
  @passing_check_statuses [Contract.passed_status(), Contract.not_required_status()]
  @passing_feedback_statuses [Contract.clear_status(), Contract.not_required_status()]

  @check_keys %{
    issue_snapshot: "issue_snapshot",
    workpad_recorded: "workpad_recorded",
    implementation_evidence: "implementation_evidence",
    validation_passed: "validation_passed",
    change_proposal_linked: "change_proposal_linked",
    change_proposal_checks: "change_proposal_checks",
    feedback_clear: "feedback_clear"
  }

  @reason_codes %{
    issue_snapshot_missing: "issue_snapshot_missing",
    workpad_record_missing: "workpad_record_missing",
    workpad_record_untrusted: "workpad_record_untrusted",
    workpad_record_stale: "workpad_record_stale",
    repo_implementation_evidence_missing: "repo_implementation_evidence_missing",
    repo_no_code_change_justification_missing: "repo_no_code_change_justification_missing",
    repo_implementation_evidence_incomplete: "repo_implementation_evidence_incomplete",
    validation_evidence_missing: "validation_evidence_missing",
    validation_not_passed: "validation_not_passed",
    validation_head_stale: "validation_head_stale",
    change_proposal_evidence_missing: "change_proposal_evidence_missing",
    change_proposal_not_ready: "change_proposal_not_ready",
    change_proposal_tracker_link_missing: "change_proposal_tracker_link_missing",
    change_proposal_checks_evidence_missing: "change_proposal_checks_evidence_missing",
    change_proposal_checks_not_passing: "change_proposal_checks_not_passing",
    change_proposal_checks_unavailable: "change_proposal_checks_unavailable",
    change_proposal_checks_unknown: "change_proposal_checks_unknown",
    change_proposal_checks_absent_without_config: "change_proposal_checks_absent_without_config",
    change_proposal_checks_observation_stale: "change_proposal_checks_observation_stale",
    change_proposal_checks_head_stale: "change_proposal_checks_head_stale",
    feedback_evidence_missing: "feedback_evidence_missing",
    feedback_action_required: "feedback_action_required"
  }

  @observed_evidence_codes %{
    workpad_recorded: "workpad.recorded",
    repo_code_change: "repo.code_change",
    repo_no_code_change_justification: "repo.no_code_change_justification",
    validation_passed: "validation.passed",
    change_proposal_linked: "change_proposal.linked",
    change_proposal_not_required: "change_proposal.not_required",
    checks_ready: "checks.ready",
    feedback_clear: "feedback.clear"
  }

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec coding_pr_delivery_policy_id() :: String.t()
  def coding_pr_delivery_policy_id, do: @coding_pr_delivery_policy_id

  @spec not_ready_error() :: String.t()
  def not_ready_error, do: @not_ready_error

  @spec passing_change_proposal_statuses() :: [String.t()]
  def passing_change_proposal_statuses, do: @passing_change_proposal_statuses

  @spec passing_check_statuses() :: [String.t()]
  def passing_check_statuses, do: @passing_check_statuses

  @spec passing_feedback_statuses() :: [String.t()]
  def passing_feedback_statuses, do: @passing_feedback_statuses

  @spec check_key(atom()) :: String.t()
  def check_key(key) when is_atom(key), do: Map.fetch!(@check_keys, key)

  @spec reason_code(atom()) :: String.t()
  def reason_code(key) when is_atom(key), do: Map.fetch!(@reason_codes, key)

  @spec observed_evidence_code(atom()) :: String.t()
  def observed_evidence_code(key) when is_atom(key), do: Map.fetch!(@observed_evidence_codes, key)
end
