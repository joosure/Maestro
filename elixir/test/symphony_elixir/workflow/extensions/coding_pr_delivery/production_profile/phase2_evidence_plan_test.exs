defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlanTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  test "builds a tiered Phase 2 evidence plan without collecting live evidence" do
    assert {:ok, plan} =
             Phase2EvidencePlan.build(:tiered_reference,
               tapd_cnb_shadow_run_id: "shadow-run-tapd-cnb-42",
               linear_cnb_shadow_run_id: "shadow-run-linear-cnb-42"
             )

    assert plan["schema"] == "coding_pr_delivery.phase2_evidence_plan.v1"
    assert plan["plan_kind"] == "tiered_reference"
    assert plan["plan_authority"] == "phase2_evidence_planning_only"
    assert plan["does_not_collect_live_evidence"] == true
    assert plan["does_not_call_providers"] == true
    assert plan["does_not_enable_production"] == true
    assert plan["live_evidence_status"] == "not_collected"

    assert [ready, tapd_cnb, linear_cnb] = plan["provider_plans"]

    assert ready["tier"] == "tier_1_reference"
    assert ready["template"] == "linear_github_ready"
    assert ready["provider_matrix_entry_ids"] == ["linear-github-ready"]
    assert ready["tracker_kinds"] == ["linear"]
    assert ready["repo_provider_kinds"] == ["github"]
    assert ready["side_effect_modes"] == ["ready_to_land_write"]
    assert ready["live_evidence_status"] == "not_collected"
    assert ready["evidence_packet_required_before_review"] == true
    assert ready["scenario_count"] > 0

    assert tapd_cnb["tier"] == "tier_2_cnb_shadow"
    assert tapd_cnb["template"] == "tapd_cnb_shadow"
    assert tapd_cnb["provider_matrix_entry_ids"] == ["tapd-cnb-shadow"]
    assert tapd_cnb["tracker_kinds"] == ["tapd"]
    assert tapd_cnb["repo_provider_kinds"] == ["cnb"]
    assert tapd_cnb["side_effect_modes"] == [OneShotContract.shadow_mode()]

    assert linear_cnb["tier"] == "tier_2_cnb_shadow"
    assert linear_cnb["template"] == "linear_cnb_shadow"
    assert linear_cnb["provider_matrix_entry_ids"] == ["linear-cnb-shadow"]
    assert linear_cnb["tracker_kinds"] == ["linear"]
    assert linear_cnb["repo_provider_kinds"] == ["cnb"]
    assert linear_cnb["side_effect_modes"] == [OneShotContract.shadow_mode()]

    assert_shadow_plan(tapd_cnb, "tapd-cnb-shadow", "shadow-run-tapd-cnb-42")
    assert_shadow_plan(linear_cnb, "linear-cnb-shadow", "shadow-run-linear-cnb-42")
  end

  test "builds a single provider Phase 2 evidence plan" do
    assert {:ok, plan} = Phase2EvidencePlan.build("linear_github_ready", plan_id: "phase2-linear-github")

    assert plan["plan_id"] == "phase2-linear-github"

    assert [%{"tier" => "tier_1_reference", "provider_matrix_entry_ids" => ["linear-github-ready"]}] =
             plan["provider_plans"]
  end

  test "rejects unknown plans before building provider evidence templates" do
    assert {:error, %{code: "coding_pr_delivery_phase2_evidence_plan_invalid", errors: [error]}} =
             Phase2EvidencePlan.build(:github_only)

    assert error.code == "unknown_plan"
    assert "tiered_reference" in error.allowed_values
  end

  test "exposes Phase 2 evidence plans through the production profile facade" do
    assert "tiered_reference" in ProductionProfile.phase2_evidence_plans()

    assert {:ok, %{"schema" => "coding_pr_delivery.phase2_evidence_plan.v1"}} =
             ProductionProfile.phase2_evidence_plan(:tiered_reference)
  end

  defp assert_shadow_plan(plan, entry_id, shadow_run_id) do
    shadow_entry =
      plan["production_claim"]["provider_matrix"]
      |> Enum.find(&(&1["id"] == entry_id))

    assert shadow_entry["shadow"]["prefix"] == OneShotContract.shadow_prefix()
    assert shadow_entry["shadow"]["run_id"] == shadow_run_id
    assert shadow_entry["shadow"]["authority"] == OneShotContract.shadow_authority()
    assert shadow_entry["shadow"]["canonical_authority"] == false

    shadow_requirement =
      plan["evidence_packet_template"]["scenario_evidence_requirements"]
      |> Enum.find(&(&1["scenario_id"] == "shadow_isolation"))

    assert shadow_requirement["provider_matrix_entry_id"] == entry_id
    assert shadow_requirement["required_evidence_kind"] == "shadow_integration"
    assert shadow_requirement["shadow"]["prefix"] == OneShotContract.shadow_prefix()
    assert shadow_requirement["shadow"]["run_id"] == shadow_run_id
    assert shadow_requirement["shadow"]["authority"] == OneShotContract.shadow_authority()
    assert shadow_requirement["shadow"]["canonical_authority"] == false

    assert shadow_requirement["no_write_flags"] == %{
             "production_write_performed" => false,
             "canonical_surface_mutated" => false
           }
  end
end
