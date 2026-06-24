defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract

  test "owns review-handoff evidence buckets and profile-specific fields" do
    assert EvidenceContract.workpad_key() == "workpad"
    assert EvidenceContract.repo_key() == "repo"
    assert EvidenceContract.change_proposal_key() == "change_proposal"
    assert EvidenceContract.validation_key() == "validation"
    assert EvidenceContract.checks_key() == "checks"
    assert EvidenceContract.feedback_key() == "feedback"
    assert EvidenceContract.linked_to_tracker_key() == "linked_to_tracker"
    assert EvidenceContract.no_code_change_justification_key() == "no_code_change_justification"
    assert EvidenceContract.code_change_kind() == "code_change"
    assert EvidenceContract.no_code_change_kind() == "no_code_change"
  end
end
