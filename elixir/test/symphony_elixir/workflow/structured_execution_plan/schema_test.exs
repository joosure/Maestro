defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.SchemaTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema

  test "valid minimal plan and item are accepted" do
    plan = minimal_plan()

    assert {:ok, ^plan} = Schema.validate(plan)
  end

  test "all structured execution plan gates default disabled" do
    assert StructuredExecutionPlan.gate_defaults() == %{
             "workflow.structured_execution_plan.enabled" => false,
             "workflow.structured_execution_plan.render_workpad" => false,
             "workflow.structured_execution_plan.review_handoff_required" => false,
             "workflow.structured_execution_plan.provider_adapters.enabled" => false
           }
  end

  test "missing required fields are rejected" do
    assert {:error, %{errors: errors}} =
             minimal_plan()
             |> Map.delete("run_id")
             |> Schema.validate()

    assert has_error?(errors, "missing_required_field", ["run_id"])

    assert {:error, %{errors: item_errors}} =
             minimal_plan()
             |> update_in(["items", Access.at(0)], &Map.delete(&1, "item_id"))
             |> Schema.validate()

    assert has_error?(item_errors, "missing_required_field", ["items", 0, "item_id"])
  end

  test "invalid plan and item enum values are rejected" do
    assert {:error, %{errors: plan_errors}} =
             minimal_plan()
             |> Map.put("status", "running")
             |> Schema.validate()

    assert has_error?(plan_errors, "invalid_enum", ["status"])

    assert {:error, %{errors: item_errors}} =
             minimal_plan()
             |> put_in(["items", Access.at(0), "status"], "done")
             |> Schema.validate()

    assert has_error?(item_errors, "invalid_enum", ["items", 0, "status"])
  end

  test "route key must belong to the workflow profile" do
    assert {:error, %{errors: errors}} =
             minimal_plan()
             |> put_in(["workflow_profile"], %{"kind" => "requirement_analysis", "version" => 1})
             |> Map.put("route_key", "developing")
             |> Schema.validate()

    assert has_error?(errors, "invalid_route_ref", ["route_key"])
  end

  test "unknown non-extension top-level and item keys are rejected" do
    assert {:error, %{errors: errors}} =
             minimal_plan()
             |> Map.put("unexpected", true)
             |> put_in(["items", Access.at(0), "unexpected"], true)
             |> Schema.validate()

    assert has_error?(errors, "unknown_key", ["unexpected"])
    assert has_error?(errors, "unknown_key", ["items", 0, "unexpected"])
  end

  test "namespaced extension keys are accepted" do
    plan =
      minimal_plan()
      |> Map.put("extensions", %{"coding_pr_delivery.review_handoff" => %{"policy" => "demo"}})
      |> put_in(["items", Access.at(0), "extensions"], %{"coding_pr_delivery.review_handoff" => %{"rank" => 1}})

    assert {:ok, ^plan} = Schema.validate(plan)
  end

  test "evidence reference shape is accepted as immutable item data" do
    plan =
      minimal_plan()
      |> put_in(["items", Access.at(0), "evidence_refs"], [evidence_ref()])

    assert {:ok, ^plan} = Schema.validate(plan)
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
      "items" => [minimal_item()],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp minimal_item do
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
  end

  defp evidence_ref do
    %{
      "evidence_id" => "evidence-test-1",
      "evidence_kind" => "repo_push",
      "source" => "tool_generated",
      "producer" => "repo_push",
      "run_id" => "run-test-1",
      "issue_id" => "TES-79",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => %{"branch" => "feature/demo", "head_sha" => "abc123"}
    }
  end

  defp has_error?(errors, code, path) do
    Enum.any?(errors, &(&1.code == code and &1.path == path))
  end
end
