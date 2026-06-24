defmodule SymphonyElixir.Workflow.Profiles.RequirementAnalysis.StructuredExecutionPlanTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Profiles.RequirementAnalysis, as: Profile
  alias SymphonyElixir.Workflow.Profiles.RequirementAnalysis.StructuredExecutionPlan, as: RequirementAnalysis
  alias SymphonyElixir.Workflow.StructuredExecutionPlan
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "builds a schema-valid requirement analysis plan with deterministic profile items" do
    assert Profile.structured_execution_plan_adoption() == RequirementAnalysis

    assert {:ok, plan} = RequirementAnalysis.build(attrs())
    assert {:ok, ^plan} = Schema.validate(plan)

    assert plan["workflow_profile"] == %{"kind" => "requirement_analysis", "version" => 1}
    assert plan["route_key"] == "analyzing"
    assert plan["lifecycle_phase"] == "in_progress"
    assert plan["status"] == "active"
    assert get_in(plan, ["extensions", RequirementAnalysis.extension_key(), "adoption_stage"]) == "profile_template"

    assert Enum.map(plan["items"], & &1["item_id"]) == RequirementAnalysis.item_ids()

    assert RequirementAnalysis.required_item_ids() == [
             "analysis.ambiguities",
             "analysis.assumptions",
             "analysis.questions",
             "analysis.tracker_summary",
             "analysis.route_selection"
           ]
  end

  test "profile required items declare evidence mapping and bounded agent-owned kinds" do
    assert {:ok, plan} = RequirementAnalysis.build(attrs())

    evidence_mapping = RequirementAnalysis.evidence_mapping()

    for item <- plan["items"] do
      assert Map.fetch!(evidence_mapping, item["item_id"]) == item["evidence_requirements"]
    end

    for item_id <- RequirementAnalysis.required_item_ids() do
      item = item(plan, item_id)
      assert item["required"] == true
      assert item["criticality"] == "profile_required"
      assert item["evidence_requirements"] != []
    end

    for item <- plan["items"], item["owned_by"] == "agent" do
      assert item["kind"] in RequirementAnalysis.agent_owned_item_kinds()
      assert item["source"] == "profile"
    end

    assert RequirementAnalysis.agent_owned_item_kinds() == ["agent_step"]
    assert item(plan, "analysis.tracker_summary")["owned_by"] == "backend"
    assert item(plan, "analysis.route_selection")["owned_by"] == "backend"
  end

  test "template plans can be stored as one active plan per requirement analysis route", %{store: store} do
    assert {:ok, plan} = RequirementAnalysis.build(attrs())
    assert {:ok, ^plan} = Store.create(plan, server: store)

    assert {:ok, ^plan} =
             Store.active_plan(plan["run_id"], RequirementAnalysis.profile(), plan["route_key"], server: store)

    assert {:ok, duplicate_plan} = RequirementAnalysis.build(attrs(plan_id: "plan-requirement-analysis-2"))

    assert {:error, %{code: "plan_conflict", active_plan_id: "plan-requirement-analysis-1"}} =
             Store.create(duplicate_plan, server: store)
  end

  test "template rejects missing required attrs, unknown attrs, invalid routes, and terminal statuses" do
    assert {:error, %{code: "missing_required_template_attrs", fields: ["run_id"]}} =
             attrs()
             |> Keyword.delete(:run_id)
             |> RequirementAnalysis.build()

    assert {:error, %{code: "unknown_template_attrs", fields: ["provider"]}} =
             attrs(provider: "github")
             |> RequirementAnalysis.build()

    assert {:error, %{code: "invalid_route_key", route_key: "developing"}} =
             attrs(route_key: "developing")
             |> RequirementAnalysis.build()

    assert {:error, %{code: "invalid_template_status", status: "closed"}} =
             attrs(status: "closed")
             |> RequirementAnalysis.build()
  end

  test "requirement analysis adoption remains non-authoritative and does not change gate defaults" do
    assert {:ok, plan} = RequirementAnalysis.build(attrs())

    evidence_kinds =
      plan["items"]
      |> Enum.flat_map(& &1["evidence_requirements"])
      |> Enum.map(& &1["evidence_kind"])

    refute Enum.any?(evidence_kinds, &String.starts_with?(&1, "repo_"))
    refute Enum.any?(plan["items"], &(&1["kind"] == "tool_evidence"))
    assert get_in(plan, ["extensions", RequirementAnalysis.extension_key(), "readiness_authority"]) == "none"

    assert StructuredExecutionPlan.gate_defaults() == %{
             Contract.enabled_gate_key() => false,
             Contract.render_workpad_gate_key() => false,
             Contract.transition_readiness_required_gate_key() => false,
             Contract.provider_adapters_enabled_gate_key() => false
           }
  end

  defp attrs(overrides \\ []) do
    [
      plan_id: "plan-requirement-analysis-1",
      run_id: "run-requirement-analysis-1",
      issue_id: "REQ-1",
      issue_identifier: "REQ-1",
      tracker_kind: "tapd",
      created_at: "2026-05-20T00:00:00Z"
    ]
    |> Keyword.merge(overrides)
  end

  defp item(plan, item_id) do
    Enum.find(plan["items"], &(&1["item_id"] == item_id))
  end
end
