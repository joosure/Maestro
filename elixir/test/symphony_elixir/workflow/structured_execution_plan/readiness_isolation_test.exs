defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ReadinessIsolationTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder, as: ReadinessEvidenceRecorder
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store, as: ReadinessStore
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store, as: PlanStore

  setup do
    if Process.whereis(ReadinessStore), do: ReadinessStore.reset()

    store = start_supervised!({PlanStore, name: nil})
    {:ok, store: store}
  end

  test "structured plan records do not change readiness evidence store behavior", %{store: store} do
    assert :ok = ReadinessStore.record("TES-79", %{"repo" => %{"head_sha" => "abc123"}})
    assert {:ok, _plan} = PlanStore.create(minimal_plan(), server: store)

    assert ReadinessStore.snapshot("TES-79") == %{
             "observations" => %{"repo" => %{"head_sha" => "abc123"}},
             "declarations" => %{},
             "metadata" => %{}
           }
  end

  test "typed tool runtime path does not record structured evidence when gate is off", %{store: store} do
    assert {:ok, _plan} = PlanStore.create(plan_with_repo_commit_item(), server: store)

    assert :ok =
             ReadinessEvidenceRecorder.record_typed_tool_result(
               "repo",
               %{"repository" => "openai/symphony"},
               "repo_commit",
               %{"run_id" => "run-test-1", "issue_id" => "TES-79"},
               {:success,
                %{
                  "data" => %{
                    "action" => "committed",
                    "headSha" => "abc123",
                    "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
                  }
                }}
             )

    assert get_in(ReadinessStore.snapshot("TES-79"), ["observations", "repo", "head_sha"]) == "abc123"
    assert {:ok, %{"items" => [%{"status" => "pending", "evidence_refs" => []}]}} = PlanStore.fetch("plan-test-1", server: store)
  end

  defp minimal_plan do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => "plan-test-1",
      "run_id" => "run-test-1",
      "issue_id" => "TES-79",
      "tracker_kind" => "linear",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "route_key" => "developing",
      "status" => "active",
      "items" => [
        %{
          "item_id" => "agent.plan",
          "parent_item_id" => nil,
          "title" => "Track implementation progress",
          "kind" => "agent_step",
          "status" => "pending",
          "required" => false,
          "criticality" => "informational",
          "owned_by" => "agent",
          "source" => "agent",
          "depends_on" => [],
          "evidence_requirements" => [],
          "evidence_refs" => [],
          "created_at" => "2026-05-20T00:00:00Z",
          "updated_at" => "2026-05-20T00:00:00Z",
          "revision" => 1
        }
      ],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp plan_with_repo_commit_item do
    minimal_plan()
    |> put_in(["items", Access.at(0), "kind"], "tool_evidence")
    |> put_in(["items", Access.at(0), "status"], "pending")
    |> put_in(["items", Access.at(0), "required"], true)
    |> put_in(["items", Access.at(0), "criticality"], "handoff_blocking")
    |> put_in(["items", Access.at(0), "owned_by"], "backend")
    |> put_in(["items", Access.at(0), "source"], "profile")
    |> put_in(["items", Access.at(0), "evidence_requirements"], [
      %{
        "evidence_kind" => "repo_commit",
        "required_fields" => ["head_sha"],
        "trust_classes" => ["tool_generated"]
      }
    ])
  end
end
