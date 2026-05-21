defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Profiles.CodingPrDelivery
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffContract

  test "coding PR delivery policy id is derived from the profile kind" do
    assert ReviewHandoffContract.coding_pr_delivery_policy_id() ==
             CodingPrDelivery.kind() <> "." <> ReviewHandoffContract.schema()
  end

  test "exposes review handoff readiness requirements" do
    assert ReviewHandoffContract.not_ready_error() == "review_handoff_not_ready"

    assert ReviewHandoffContract.passing_change_proposal_statuses() == [
             Contract.linked_status(),
             Contract.created_status(),
             Contract.updated_status()
           ]

    assert ReviewHandoffContract.passing_check_statuses() == [
             Contract.passed_status(),
             Contract.not_required_status()
           ]

    assert ReviewHandoffContract.passing_feedback_statuses() == [
             Contract.clear_status(),
             Contract.not_required_status()
           ]
  end

  test "exposes review handoff machine-readable check identifiers" do
    assert ReviewHandoffContract.check_key(:workpad_recorded) == "workpad_recorded"
    assert ReviewHandoffContract.reason_code(:workpad_record_stale) == "workpad_record_stale"
    assert ReviewHandoffContract.reason_code(:validation_head_stale) == "validation_head_stale"
    assert ReviewHandoffContract.observed_evidence_code(:checks_ready) == "checks.ready"
  end
end
