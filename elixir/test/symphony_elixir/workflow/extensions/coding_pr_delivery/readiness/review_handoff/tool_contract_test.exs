defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ToolContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ToolContract

  test "classifies readiness evidence tools by semantic evidence kind" do
    assert ToolContract.evidence_kind(ToolContract.linear_upsert_workpad_tool()) == :workpad
    assert ToolContract.evidence_kind(ToolContract.tapd_upsert_workpad_tool()) == :workpad
    assert ToolContract.evidence_kind(ToolContract.repo_read_change_proposal_checks_tool()) == :repo_change_proposal_checks
    assert ToolContract.evidence_kind("unknown_tool") == nil
  end

  test "exposes all readiness evidence tool names" do
    assert ToolContract.repo_read_change_proposal_checks_tool() in ToolContract.evidence_tool_names()
  end
end
