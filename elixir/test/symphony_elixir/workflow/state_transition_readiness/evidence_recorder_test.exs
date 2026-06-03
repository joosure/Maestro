defmodule SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorderTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.DynamicTool.EvidencePayload
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
      %{"issue_id" => "issue-1"},
      {:success,
       %{}
       |> EvidencePayload.attach(
         EvidencePayload.workpad(%{
           "id" => "linear:issue:issue-1:workpad",
           "updated" => true,
           "created" => false
         })
       )}
    )

    workpad = get_in(Store.snapshot("issue-1"), ["observations", "workpad"])

    assert workpad["status"] == "updated"
    assert workpad["source"] == "typed_tool_observed"
    assert workpad["workpad_id"] == "linear:issue:issue-1:workpad"
    refute Map.has_key?(workpad, "sections")
  end

  test "records tracker workpad writes from canonical typed-tool evidence" do
    EvidenceRecorder.record_typed_tool_result(
      "tapd",
      %{},
      ReviewHandoffToolContract.tapd_upsert_workpad_tool(),
      %{"issue_id" => "issue-1"},
      {:success,
       %{"comment" => %{"id" => "provider-native-comment"}}
       |> EvidencePayload.attach(
         EvidencePayload.workpad(%{
           "id" => "tapd:issue:issue-1:workpad",
           "updated" => true,
           "created" => false
         })
       )}
    )

    workpad = get_in(Store.snapshot("issue-1"), ["observations", "workpad"])

    assert workpad["status"] == "updated"
    assert workpad["source"] == "typed_tool_observed"
    assert workpad["workpad_id"] == "tapd:issue:issue-1:workpad"
    assert is_binary(workpad["updated_at"])
  end

  test "records tracker change proposal links from canonical typed-tool evidence" do
    EvidenceRecorder.record_typed_tool_result(
      "tapd",
      %{},
      "tapd_attach_change_proposal",
      %{"issue_id" => "issue-1"},
      {:success,
       %{}
       |> EvidencePayload.attach(
         EvidencePayload.tracker_change_proposal(
           %{"id" => "tapd-workpad:comment-1", "url" => "https://example.test/pulls/1"},
           %{"repo_provider_kind" => "cnb", "repository" => "org/repo"}
         )
       )}
    )

    change_proposal = get_in(Store.snapshot("issue-1"), ["observations", "change_proposal"])

    assert change_proposal["status"] == "linked"
    assert change_proposal["source"] == "tracker_observed"
    assert change_proposal["id"] == "tapd-workpad:comment-1"
    assert change_proposal["url"] == "https://example.test/pulls/1"
    assert change_proposal["provider_kind"] == "cnb"
    assert change_proposal["repository"] == "org/repo"
    assert change_proposal["linked_to_tracker"] == true
  end

  test "records unavailable change-proposal checks when no check runs are found without trusted policy" do
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

    checks = get_in(Store.snapshot("issue-1"), ["observations", "checks"])

    assert checks["status"] == "unavailable"
    refute checks["head_sha"]
  end

  test "records not-required change-proposal checks only from trusted profile policy" do
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
       }},
      tool_context: %{workflow_settings: no_change_proposal_checks_workflow_settings()}
    )

    checks = get_in(Store.snapshot("issue-1"), ["observations", "checks"])

    assert checks["status"] == "not_required"
    refute checks["head_sha"]
  end

  test "records completed successful change-proposal checks as passed" do
    EvidenceRecorder.record_typed_tool_result(
      "repo_provider",
      %{},
      ReviewHandoffToolContract.repo_read_change_proposal_checks_tool(),
      %{"issue_id" => "issue-1"},
      {:success,
       %{
         "data" => %{
           "checks" => %{
             "runs" => [
               %{
                 "name" => "cnb/pull_request/pipeline-1",
                 "status" => "completed",
                 "conclusion" => "success",
                 "summary" => "success [5.4s]"
               }
             ],
             "summary" => %{"unknown" => 1},
             "headSha" => "head-1"
           }
         }
       }}
    )

    checks = get_in(Store.snapshot("issue-1"), ["observations", "checks"])

    assert checks["status"] == "passed"
    assert checks["head_sha"] == "head-1"
  end

  test "records run-scoped handoff evidence on the issue key for continuation runs" do
    EvidenceRecorder.record_typed_tool_result(
      "repo",
      %{},
      "repo_commit",
      %{"issue_id" => "issue-1"},
      {:success,
       %{
         "data" => %{
           "action" => "committed",
           "headSha" => "abc123",
           "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
         }
       }},
      run_id: "run-1"
    )

    assert get_in(Store.snapshot("issue-1"), ["observations", "repo", "head_sha"]) == "abc123"

    assert get_in(Store.snapshot(Store.scope_issue_keys("run-1", "issue-1")), ["observations", "repo", "head_sha"]) ==
             "abc123"
  end

  defp no_change_proposal_checks_workflow_settings do
    %{
      workflow: %{
        profile: %{
          "kind" => "coding_pr_delivery",
          "version" => 1,
          "options" => %{
            "readiness" => %{
              "review_handoff" => %{
                "change_proposal_checks" => %{
                  "mode" => "not_required"
                }
              }
            }
          }
        }
      }
    }
  end
end
