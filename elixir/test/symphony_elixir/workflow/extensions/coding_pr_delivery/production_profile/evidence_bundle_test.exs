defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceBundleTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceBundle
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  test "marks a single-provider Phase 2 bundle ready when preflight and evidence pass" do
    phase2_plan = phase2_plan(:linear_cnb_shadow)
    preflight_report = passed_preflight_report(phase2_plan)
    evidence_packet = completed_evidence_packet(List.first(phase2_plan["provider_plans"]))

    assert {:ok, bundle} =
             EvidenceBundle.build(phase2_plan,
               preflight_report: preflight_report,
               evidence_packets: [evidence_packet]
             )

    assert bundle["schema"] == "coding_pr_delivery.production_evidence_bundle.v1"
    assert bundle["status"] == "ready_for_phase4_review"
    assert bundle["phase4_ready"] == true
    assert bundle["preflight"]["status"] == "passed"
    assert bundle["evidence_packets"]["valid_count"] == 1
    assert bundle["evidence_packets"]["invalid_count"] == 0
    assert bundle["blockers"] == []
    assert bundle["does_not_read_evidence_files"] == true
    assert bundle["does_not_call_providers"] == true
    assert bundle["does_not_enable_production"] == true

    assert [
             %{
               "template" => "linear_cnb_shadow",
               "evidence_packet_status" => "valid",
               "review_packet_template_ready" => true
             }
           ] = bundle["provider_bundle_statuses"]
  end

  test "keeps tiered plans blocked until every provider plan has evidence" do
    phase2_plan = phase2_plan(:tiered_reference)
    preflight_report = passed_preflight_report(phase2_plan)
    linear_cnb_plan = Enum.find(phase2_plan["provider_plans"], &(&1["template"] == "linear_cnb_shadow"))
    evidence_packet = completed_evidence_packet(linear_cnb_plan)

    assert {:ok, bundle} =
             EvidenceBundle.build(phase2_plan,
               preflight_report: preflight_report,
               evidence_packets: [evidence_packet]
             )

    assert bundle["status"] == "blocked"
    assert bundle["phase4_ready"] == false
    assert Enum.any?(bundle["blockers"], &(&1["code"] == "provider_evidence_packet_missing" and &1["template"] == "linear_github_ready"))
    assert Enum.any?(bundle["blockers"], &(&1["code"] == "provider_evidence_packet_missing" and &1["template"] == "tapd_cnb_shadow"))
  end

  test "blocks invalid or blocked preflight metadata before Phase 4 review" do
    phase2_plan = phase2_plan(:linear_cnb_shadow)
    evidence_packet = completed_evidence_packet(List.first(phase2_plan["provider_plans"]))

    assert {:ok, missing_preflight} = EvidenceBundle.build(phase2_plan, evidence_packets: [evidence_packet])
    assert Enum.any?(missing_preflight["blockers"], &(&1["code"] == "provider_preflight_report_required"))

    assert {:ok, blocked_preflight} =
             EvidenceBundle.build(phase2_plan,
               preflight_report: blocked_preflight_report(phase2_plan),
               evidence_packets: [evidence_packet]
             )

    assert Enum.any?(blocked_preflight["blockers"], &(&1["code"] == "provider_preflight_blocked"))
  end

  test "blocks mismatched evidence requests and unmatched evidence packets" do
    phase2_plan = phase2_plan(:linear_cnb_shadow)
    preflight_report = passed_preflight_report(phase2_plan)
    other_plan = phase2_plan(:tapd_cnb_shadow)
    other_evidence_packet = completed_evidence_packet(List.first(other_plan["provider_plans"]))

    assert {:ok, request} = ProductionProfile.production_evidence_request(:tapd_cnb_shadow)

    assert {:ok, bundle} =
             EvidenceBundle.build(phase2_plan,
               evidence_request: request,
               preflight_report: preflight_report,
               evidence_packets: [other_evidence_packet]
             )

    assert bundle["status"] == "blocked"
    assert Enum.any?(bundle["blockers"], &(&1["code"] == "evidence_request_invalid"))
    assert Enum.any?(bundle["blockers"], &(&1["code"] == "completed_evidence_packet_unmatched"))
    assert Enum.any?(bundle["blockers"], &(&1["code"] == "provider_evidence_packet_missing"))
  end

  test "exposes evidence bundle readiness through the production profile facade" do
    phase2_plan = phase2_plan(:linear_cnb_shadow)

    assert {:ok, %{"schema" => "coding_pr_delivery.production_evidence_bundle.v1"}} =
             ProductionProfile.production_evidence_bundle(phase2_plan)
  end

  test "rejects invalid options without provider calls" do
    assert {:error, %{code: "coding_pr_delivery_evidence_bundle_invalid", errors: [error]}} =
             EvidenceBundle.build(:linear_cnb_shadow, :not_keyword)

    assert error.code == "invalid_options"
  end

  defp phase2_plan(plan_id) do
    assert {:ok, plan} =
             ProductionProfile.phase2_evidence_plan(plan_id,
               tapd_cnb_shadow_run_id: "bundle-tapd-cnb-shadow",
               linear_cnb_shadow_run_id: "bundle-linear-cnb-shadow"
             )

    plan
  end

  defp passed_preflight_report(phase2_plan) do
    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => preflight_results(phase2_plan, "passed"),
      "explicit_non_claims" => [
        "preflight_report_does_not_collect_live_provider_evidence",
        "preflight_report_does_not_enable_production"
      ]
    }
  end

  defp blocked_preflight_report(phase2_plan) do
    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => preflight_results(phase2_plan, "blocked"),
      "explicit_non_claims" => [
        "preflight_report_does_not_collect_live_provider_evidence",
        "preflight_report_does_not_enable_production"
      ]
    }
  end

  defp preflight_results(phase2_plan, status) do
    phase2_plan
    |> Map.fetch!("provider_plans")
    |> Enum.flat_map(fn provider_plan ->
      provider_plan
      |> get_in(["read_only_preflight", "commands"])
      |> Enum.map(&preflight_result(provider_plan, &1, status))
    end)
  end

  defp preflight_result(provider_plan, command, "passed") do
    %{
      "template" => Map.fetch!(provider_plan, "template"),
      "command_id" => Map.fetch!(command, "id"),
      "target" => Map.fetch!(command, "target"),
      "provider_kind" => Map.fetch!(command, "provider_kind"),
      "status" => "passed",
      "ran_at" => "2026-06-26T04:10:00Z",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false,
      "missing_prerequisites" => [],
      "evidence_files" => ["evidence/preflight/#{Map.fetch!(provider_plan, "template")}/#{Map.fetch!(command, "id")}.md"]
    }
  end

  defp preflight_result(provider_plan, command, "blocked") do
    %{
      "template" => Map.fetch!(provider_plan, "template"),
      "command_id" => Map.fetch!(command, "id"),
      "target" => Map.fetch!(command, "target"),
      "provider_kind" => Map.fetch!(command, "provider_kind"),
      "status" => "blocked",
      "blocker_code" => "missing_preflight_prerequisite",
      "missing_prerequisites" => [first_prerequisite(command)],
      "ran_at" => "2026-06-26T04:10:00Z",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false,
      "evidence_files" => ["evidence/preflight/#{Map.fetch!(provider_plan, "template")}/#{Map.fetch!(command, "id")}.md"]
    }
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
          "evidence_kind" => evidence_kind(entry),
          "collector" => "provider-integration-owner",
          "collected_at" => "2026-06-26T04:30:00Z",
          "evidence_files" => ["evidence/live/#{entry["entry_id"]}/#{scenario["id"]}.md"],
          "production_write_performed" => false,
          "canonical_surface_mutated" => false,
          "shadow" => shadow(entry)
        }
      end)
    end)
  end

  defp evidence_kind(entry) do
    if entry["side_effect_mode"] == OneShotContract.shadow_mode() do
      "shadow_integration"
    else
      "real_integration"
    end
  end

  defp shadow(entry) do
    if entry["side_effect_mode"] == OneShotContract.shadow_mode() do
      shadow_metadata(entry)
    else
      nil
    end
  end

  defp shadow_metadata(entry) do
    %{
      "prefix" => OneShotContract.shadow_prefix(),
      "run_id" => get_in(entry, ["shadow_requirements", "run_id"]) || "bundle-shadow-run",
      "authority" => OneShotContract.shadow_authority(),
      "canonical_authority" => false,
      "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
    }
  end

  defp non_claim_acknowledgements(runbook) do
    Enum.map(runbook["entries"], fn entry ->
      %{
        "provider_matrix_entry_id" => entry["entry_id"],
        "non_claims" => entry["non_claims"],
        "owner" => "provider-integration-owner",
        "acknowledged_at" => "2026-06-26T04:30:00Z"
      }
    end)
  end

  defp first_prerequisite(command) do
    command
    |> Map.take(["required_env", "required_auth", "required_targets", "required_runtime"])
    |> Map.values()
    |> Enum.flat_map(fn
      values when is_list(values) -> values
      _value -> []
    end)
    |> List.first()
  end
end
