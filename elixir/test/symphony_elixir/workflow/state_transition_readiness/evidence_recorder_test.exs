defmodule SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorderTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffToolContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store

  setup do
    if Process.whereis(Store), do: Store.reset()
    :ok
  end

  test "records workpad writes without trusting agent-declared section completion" do
    EvidenceRecorder.record_typed_tool_result(
      "linear",
      %{},
      ReviewHandoffToolContract.linear_upsert_workpad_tool(),
      %{
        "issue_id" => "issue-1",
        "sections" => [
          %{"key" => "plan", "status" => "complete"},
          %{"key" => "acceptance_criteria", "status" => "complete"},
          %{"key" => "validation", "status" => "complete"}
        ]
      },
      {:success,
       %{
         "data" => %{
           "comment" => %{
             "id" => "comment-1",
             "updated" => true,
             "created" => false
           }
         }
       }}
    )

    workpad = get_in(Store.snapshot("issue-1"), ["observations", "workpad"])

    assert workpad["status"] == "updated"
    assert workpad["source"] == "typed_tool_observed"
    assert workpad["comment_id"] == "comment-1"
    refute Map.has_key?(workpad, "sections")
  end

  test "records not-required provider checks without a head sha" do
    EvidenceRecorder.record_typed_tool_result(
      "repo_provider",
      %{},
      ReviewHandoffToolContract.repo_read_change_proposal_checks_tool(),
      %{"issue_id" => "issue-1"},
      {:success,
       %{
         "data" => %{
           "checks" => %{
             "runs" => [],
             "summary" => %{},
             "headSha" => "stale-head"
           }
         }
       }}
    )

    assert get_in(Store.snapshot("issue-1"), ["observations", "checks", "status"]) == "not_required"
    refute get_in(Store.snapshot("issue-1"), ["observations", "checks", "head_sha"])
  end
end
