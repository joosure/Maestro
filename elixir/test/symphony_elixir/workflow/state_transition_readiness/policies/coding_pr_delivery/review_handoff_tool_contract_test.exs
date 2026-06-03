defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffToolContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffToolContract

  test "classifies readiness evidence tools by semantic evidence kind" do
    assert ReviewHandoffToolContract.evidence_kind(ReviewHandoffToolContract.linear_upsert_workpad_tool()) == :workpad
    assert ReviewHandoffToolContract.evidence_kind(ReviewHandoffToolContract.tapd_upsert_workpad_tool()) == :workpad
    assert ReviewHandoffToolContract.evidence_kind(ReviewHandoffToolContract.repo_read_change_proposal_checks_tool()) == :repo_change_proposal_checks
    assert ReviewHandoffToolContract.evidence_kind("unknown_tool") == nil
  end

  test "exposes all readiness evidence tool names" do
    assert ReviewHandoffToolContract.repo_read_change_proposal_checks_tool() in ReviewHandoffToolContract.evidence_tool_names()
  end
end
