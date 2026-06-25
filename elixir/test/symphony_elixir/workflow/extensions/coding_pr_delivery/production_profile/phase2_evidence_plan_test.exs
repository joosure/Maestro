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
    assert_read_only_preflight(ready, "linear", "github")

    assert tapd_cnb["tier"] == "tier_2_cnb_shadow"
    assert tapd_cnb["template"] == "tapd_cnb_shadow"
    assert tapd_cnb["provider_matrix_entry_ids"] == ["tapd-cnb-shadow"]
    assert tapd_cnb["tracker_kinds"] == ["tapd"]
    assert tapd_cnb["repo_provider_kinds"] == ["cnb"]
    assert tapd_cnb["side_effect_modes"] == [OneShotContract.shadow_mode()]
    assert_read_only_preflight(tapd_cnb, "tapd", "cnb")

    assert linear_cnb["tier"] == "tier_2_cnb_shadow"
    assert linear_cnb["template"] == "linear_cnb_shadow"
    assert linear_cnb["provider_matrix_entry_ids"] == ["linear-cnb-shadow"]
    assert linear_cnb["tracker_kinds"] == ["linear"]
    assert linear_cnb["repo_provider_kinds"] == ["cnb"]
    assert linear_cnb["side_effect_modes"] == [OneShotContract.shadow_mode()]
    assert_read_only_preflight(linear_cnb, "linear", "cnb")

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

  defp assert_read_only_preflight(plan, tracker_kind, repo_provider_kind) do
    assert %{
             "status" => "not_run",
             "does_not_collect_live_evidence" => true,
             "does_not_mutate_workflow_state" => true,
             "does_not_enable_production" => true,
             "commands" => commands
           } = plan["read_only_preflight"]

    assert [%{"target" => "tracker"} = tracker, %{"target" => "repo_provider"} = repo_provider] = commands

    assert tracker["provider_kind"] == tracker_kind
    assert tracker["side_effect_mode"] == "read_only"
    assert tracker["requires_write_confirmation"] == false
    assert tracker["does_not_write"] == true
    assert tracker["command"] =~ "mix tracker.smoke"
    assert_required_tracker_env(tracker_kind, tracker["required_env"])

    assert repo_provider["provider_kind"] == repo_provider_kind
    assert repo_provider["side_effect_mode"] == "read_only"
    assert repo_provider["requires_destructive_flag"] == false
    assert repo_provider["does_not_write"] == true
    assert repo_provider["command"] =~ "mix repo_provider.smoke"
    assert_required_repo_provider_auth(repo_provider_kind, repo_provider)
  end

  defp assert_required_tracker_env("linear", required_env) do
    assert required_env == ["LINEAR_API_KEY", "LINEAR_PROJECT_SLUG"]
  end

  defp assert_required_tracker_env("tapd", required_env) do
    assert required_env == ["TAPD_API_USER", "TAPD_API_PASSWORD", "TAPD_WORKSPACE_ID"]
  end

  defp assert_required_repo_provider_auth("github", repo_provider) do
    assert repo_provider["required_env"] == []
    assert repo_provider["required_auth"] == ["gh auth status"]
    assert repo_provider["required_targets"] == ["repo_slug", "change_proposal_number"]
  end

  defp assert_required_repo_provider_auth("cnb", repo_provider) do
    assert repo_provider["required_env"] == ["CNB_TOKEN"]
    assert repo_provider["required_auth"] == []
    assert repo_provider["required_targets"] == ["repo_slug", "change_proposal_number"]
  end
end
