defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceHandoffTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceHandoff
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  test "builds a blocked provider-owner handoff package for missing evidence" do
    assert {:ok, handoff} = EvidenceHandoff.build(:tiered_reference)

    assert handoff["schema"] == "coding_pr_delivery.production_evidence_handoff.v1"
    assert handoff["status"] == "blocked_pending_external_evidence"
    assert handoff["phase4_ready"] == false
    assert handoff["provider_plan_count"] == 3
    assert handoff["preflight"]["status"] == "missing"
    assert handoff["evidence_bundle"]["status"] == "blocked"
    assert handoff["evidence_bundle"]["blocker_count"] > 0

    assert Enum.sort(handoff["external_input_summary"]["required_env"]) == [
             "CNB_TOKEN",
             "LINEAR_API_KEY",
             "LINEAR_PROJECT_SLUG",
             "TAPD_API_PASSWORD",
             "TAPD_API_USER",
             "TAPD_WORKSPACE_ID"
           ]

    assert Enum.any?(
             handoff["provider_handoffs"],
             &(&1["template"] == "linear_cnb_shadow" and &1["evidence_packet_status"] == "missing")
           )

    assert Enum.any?(
             handoff["operator_commands"],
             &(&1["command_id"] ==
                 "symphony.workflow.extension.coding_pr_delivery.production_profile_evidence_handoff")
           )

    assert handoff["does_not_collect_live_evidence"] == true
    assert handoff["does_not_read_evidence_files"] == true
    assert handoff["does_not_call_providers"] == true
    assert handoff["does_not_enable_production"] == true
    assert handoff["raw_input_included"] == false
    assert handoff["normalized_artifacts_included"] == false
  end

  test "marks handoff ready when preflight and evidence bundle are ready" do
    phase2_plan = phase2_plan(:linear_cnb_shadow)
    preflight_report = passed_preflight_report(phase2_plan)
    evidence_packet = completed_evidence_packet(List.first(phase2_plan["provider_plans"]))

    assert {:ok, handoff} =
             EvidenceHandoff.build(phase2_plan,
               preflight_report: preflight_report,
               evidence_packets: [evidence_packet]
             )

    assert handoff["status"] == "ready_for_phase4_review"
    assert handoff["phase4_ready"] == true
    assert handoff["required_next_step"] == "build and validate the Phase 4 review packet with owner sign-off"
    assert handoff["preflight"]["status"] == "passed"
    assert handoff["evidence_bundle"]["phase4_ready"] == true
    assert handoff["blockers"] == []

    assert [
             %{
               "template" => "linear_cnb_shadow",
               "evidence_packet_status" => "valid",
               "matching_evidence_packet_count" => 1,
               "review_packet_template_ready" => true
             }
           ] = handoff["provider_handoffs"]
  end

  test "exposes evidence handoff through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_evidence_handoff.v1"}} =
             ProductionProfile.production_evidence_handoff(:linear_cnb_shadow)
  end

  test "rejects invalid options without provider calls" do
    assert {:error, %{code: "coding_pr_delivery_evidence_handoff_invalid", errors: [error]}} =
             EvidenceHandoff.build(:linear_cnb_shadow, :not_keyword)

    assert error.code == "invalid_options"
  end

  defp phase2_plan(plan_id) do
    assert {:ok, plan} =
             ProductionProfile.phase2_evidence_plan(plan_id,
               tapd_cnb_shadow_run_id: "handoff-tapd-cnb-shadow",
               linear_cnb_shadow_run_id: "handoff-linear-cnb-shadow"
             )

    plan
  end

  defp passed_preflight_report(phase2_plan) do
    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => preflight_results(phase2_plan),
      "explicit_non_claims" => [
        "preflight_report_does_not_collect_live_provider_evidence",
        "preflight_report_does_not_enable_production"
      ]
    }
  end

  defp preflight_results(phase2_plan) do
    phase2_plan
    |> Map.fetch!("provider_plans")
    |> Enum.flat_map(fn provider_plan ->
      provider_plan
      |> get_in(["read_only_preflight", "commands"])
      |> Enum.map(fn command ->
        %{
          "template" => Map.fetch!(provider_plan, "template"),
          "command_id" => Map.fetch!(command, "id"),
          "target" => Map.fetch!(command, "target"),
          "provider_kind" => Map.fetch!(command, "provider_kind"),
          "status" => "passed",
          "ran_at" => "2026-06-26T06:30:00Z",
          "side_effect_mode" => "read_only",
          "write_performed" => false,
          "production_enabled" => false,
          "missing_prerequisites" => [],
          "evidence_files" => ["evidence/preflight/#{Map.fetch!(command, "id")}.md"]
        }
      end)
    end)
  end

  defp completed_evidence_packet(provider_plan) do
    runbook = Map.fetch!(provider_plan, "evidence_runbook")

    %{
      "production_claim" => Map.fetch!(provider_plan, "production_claim"),
      "scenario_evidence" => scenario_evidence(runbook),
      "non_claim_acknowledgements" => non_claim_acknowledgements(runbook)
    }
  end

  defp scenario_evidence(runbook) do
    Enum.flat_map(runbook["entries"], fn entry ->
      Enum.map(entry["scenario_checklist"], fn scenario ->
        %{
          "provider_matrix_entry_id" => entry["entry_id"],
          "scenario_id" => scenario["id"],
          "status" => "passed",
          "evidence_kind" => "shadow_integration",
          "collector" => "provider-integration-owner",
          "collected_at" => "2026-06-26T06:30:00Z",
          "evidence_files" => ["evidence/live/#{entry["entry_id"]}/#{scenario["id"]}.md"],
          "production_write_performed" => false,
          "canonical_surface_mutated" => false,
          "shadow" => %{
            "prefix" => OneShotContract.shadow_prefix(),
            "run_id" => get_in(entry, ["shadow_requirements", "run_id"]) || "handoff-linear-cnb-shadow",
            "authority" => OneShotContract.shadow_authority(),
            "canonical_authority" => false,
            "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
          }
        }
      end)
    end)
  end

  defp non_claim_acknowledgements(runbook) do
    Enum.map(runbook["entries"], fn entry ->
      %{
        "provider_matrix_entry_id" => entry["entry_id"],
        "non_claims" => entry["non_claims"],
        "owner" => "provider-integration-owner",
        "acknowledged_at" => "2026-06-26T06:30:00Z"
      }
    end)
  end
end
