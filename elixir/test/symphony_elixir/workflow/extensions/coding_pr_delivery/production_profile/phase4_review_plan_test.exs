defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase4ReviewPlanTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase4ReviewPlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @owning_source_specs [
    "specs/workflow/profiles/coding_pr_delivery/profile_spec.md",
    "specs/workflow/typed_workflow_tools/conformance_spec.md",
    "specs/workflow/profiles/coding_pr_delivery/review_handoff_readiness_policy/conformance_spec.md",
    "specs/workflow/extensions/coding_pr_delivery/reconciliation/conformance_spec.md",
    "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md",
    "specs/workflow/execution_plan_adoption/readiness_spec.md",
    "specs/workflow/execution_plan_adoption/production_profile_spec.md"
  ]

  test "builds a blocked Phase 4 review plan from tiered Phase 2 evidence plans" do
    assert {:ok, plan} =
             Phase4ReviewPlan.build(:tiered_reference,
               tapd_cnb_shadow_run_id: "shadow-run-tapd-cnb-42",
               linear_cnb_shadow_run_id: "shadow-run-linear-cnb-42"
             )

    assert plan["schema"] == "coding_pr_delivery.phase4_review_plan.v1"
    assert plan["phase2_plan_kind"] == "tiered_reference"
    assert plan["review_authority"] == "phase4_review_planning_only"
    assert plan["phase4_ready"] == false
    assert plan["review_decision_status"] == "blocked"
    assert plan["does_not_collect_live_evidence"] == true
    assert plan["does_not_read_evidence_files"] == true
    assert plan["does_not_call_providers"] == true
    assert plan["does_not_approve_production"] == true
    assert plan["does_not_enable_production"] == true

    assert [ready, tapd_cnb, linear_cnb] = plan["provider_review_plans"]

    assert ready["template"] == "linear_github_ready"
    assert ready["required_evidence_kinds"] == ["real_integration"]
    assert ready["review_packet_blocked_until_completed_evidence"] == true

    assert_shadow_review_plan(tapd_cnb, "tapd_cnb_shadow", "shadow-run-tapd-cnb-42")
    assert_shadow_review_plan(linear_cnb, "linear_cnb_shadow", "shadow-run-linear-cnb-42")

    blockers = plan["blocking_requirements"]
    assert Enum.count(blockers, &(&1["code"] == "completed_evidence_packet_required")) == 3
    assert Enum.any?(blockers, &(&1["code"] == "scrubbing_test_results_required"))
    assert Enum.any?(blockers, &(&1["code"] == "owner_signoffs_required"))
  end

  test "projects Phase 4 packet requirements without approving production" do
    assert {:ok, plan} = Phase4ReviewPlan.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: "linear-shadow-99")

    requirements = plan["review_packet_requirements"]

    assert "specs/workflow/profiles/coding_pr_delivery/profile_spec.md" in requirements["changed_source_specs"]
    assert "fill-implementation-pr-or-local-patch-ref" in requirements["implementation_refs"]
    assert "fill-deterministic-test-matrix" in requirements["deterministic_test_matrix"]

    assert requirements["rollback_instructions"]["external_transition_readiness_gate"] ==
             Gates.transition_readiness_required_gate_key()

    assert requirements["rollback_instructions"]["legacy_review_handoff_required_mapping"] == true
    assert "review_packet_render" in requirements["scrubbing_pipeline"]["required_boundaries"]
    assert requirements["scrubbing_pipeline"]["failure_behavior"] == "fail_closed"
    assert requirements["operator_inspection"]["contains_raw_evidence_payload"] == false
    assert requirements["operator_inspection"]["workpad_markdown_authoritative"] == false
    assert requirements["authority_boundaries"]["raw_provider_passthrough_authorized"] == false
    assert "fill-owner-signoffs" in requirements["owner_signoffs"]

    assert [evidence_packet] = requirements["completed_evidence_packets"]
    assert evidence_packet["template"] == "linear_cnb_shadow"
    assert evidence_packet["live_evidence_status"] == "not_collected"
    assert evidence_packet["required_evidence_kinds"] == ["shadow_integration"]
  end

  test "cites the owning specs required by the hardening review packet" do
    assert {:ok, plan} = Phase4ReviewPlan.build(:tiered_reference)

    source_specs = plan["review_packet_requirements"]["changed_source_specs"]

    assert source_specs == @owning_source_specs
    assert "specs/workflow/typed_workflow_tools/conformance_spec.md" in source_specs

    assert "specs/workflow/profiles/coding_pr_delivery/review_handoff_readiness_policy/conformance_spec.md" in source_specs

    refute "specs/workflow/extensions/coding_pr_delivery/typed_workflow_tools/conformance_spec.md" in source_specs

    refute "specs/workflow/extensions/coding_pr_delivery/review_handoff_readiness_policy/conformance_spec.md" in source_specs
  end

  test "accepts a prebuilt Phase 2 evidence plan" do
    assert {:ok, phase2_plan} =
             Phase2EvidencePlan.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: "linear-shadow-from-plan")

    assert {:ok, review_plan} = Phase4ReviewPlan.build(phase2_plan)

    assert review_plan["phase2_plan_id"] == phase2_plan["plan_id"]
    assert [provider_plan] = review_plan["provider_review_plans"]
    assert provider_plan["shadow"]["run_id"] == "linear-shadow-from-plan"
  end

  test "rejects malformed Phase 2 review inputs" do
    assert {:error, %{code: "coding_pr_delivery_phase2_evidence_plan_invalid"}} =
             Phase4ReviewPlan.build(:github_only)

    assert {:error, %{code: "coding_pr_delivery_phase4_review_plan_invalid", errors: [error]}} =
             Phase4ReviewPlan.build(%{
               "schema" => "coding_pr_delivery.phase2_evidence_plan.v1",
               "provider_plans" => []
             })

    assert error.code == "missing_provider_plans"
  end

  test "exposes Phase 4 review plans through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.phase4_review_plan.v1"}} =
             ProductionProfile.phase4_review_plan(:tiered_reference)
  end

  defp assert_shadow_review_plan(plan, template, shadow_run_id) do
    assert plan["template"] == template
    assert plan["required_evidence_kinds"] == ["shadow_integration"]
    assert plan["review_packet_blocked_until_completed_evidence"] == true
    assert plan["shadow"]["prefix"] == OneShotContract.shadow_prefix()
    assert plan["shadow"]["run_id"] == shadow_run_id
    assert plan["shadow"]["authority"] == OneShotContract.shadow_authority()
    assert plan["shadow"]["canonical_authority"] == false
    assert OneShotContract.shadow_allowed_destinations() == plan["shadow"]["allowed_destinations"]
    assert Enum.any?(plan["required_evidence_files"], &String.contains?(&1, template_id(template)))
  end

  defp template_id("tapd_cnb_shadow"), do: "tapd-cnb-shadow"
  defp template_id("linear_cnb_shadow"), do: "linear-cnb-shadow"
end
