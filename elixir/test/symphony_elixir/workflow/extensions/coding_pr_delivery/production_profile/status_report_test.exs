defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.StatusReportTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.StatusReport

  test "summarizes missing preflight reports as bounded Phase 4 blockers" do
    assert {:ok, report} = StatusReport.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: "status-shadow-1")

    assert report["schema"] == "coding_pr_delivery.production_profile_status.v1"
    assert report["status"] == "blocked"
    assert report["phase4_ready"] == false
    assert report["preflight"]["provided"] == false
    assert report["does_not_call_providers"] == true
    assert report["does_not_enable_production"] == true
    assert report["raw_input_included"] == false
    assert [%{"template" => "linear_cnb_shadow"}] = report["provider_entries"]

    assert Enum.any?(report["blockers"], &(&1["code"] == "provider_preflight_report_required"))
    assert Enum.any?(report["blockers"], &(&1["code"] == "completed_evidence_packet_required"))
  end

  test "replaces preflight-required blockers with concrete blocked preflight prerequisites" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_cnb_shadow)
    blocked_preflight = preflight_report(phase2_plan, "blocked")

    assert {:ok, report} = StatusReport.build(phase2_plan, preflight_report: blocked_preflight)

    assert report["status"] == "blocked"
    assert report["preflight"]["provided"] == true
    assert report["preflight"]["valid"] == true
    assert report["preflight"]["status"] == "blocked"
    assert report["preflight"]["blocked_count"] == 2
    assert Enum.all?(report["preflight"]["blocked_results"], &(&1["missing_prerequisites"] != []))

    refute Enum.any?(report["blockers"], &(&1["code"] == "provider_preflight_report_required"))
    assert Enum.count(report["blockers"], &(&1["code"] == "provider_preflight_blocked")) == 2
    assert Enum.any?(report["blockers"], &(&1["provider_kind"] == "linear"))
    assert Enum.any?(report["blockers"], &(&1["provider_kind"] == "cnb"))
  end

  test "removes preflight blockers when a passed preflight report covers the plan" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_cnb_shadow)
    passed_preflight = preflight_report(phase2_plan, "passed")

    assert {:ok, report} = StatusReport.build(phase2_plan, preflight_report: passed_preflight)

    assert report["status"] == "blocked"
    assert report["preflight"]["valid"] == true
    assert report["preflight"]["status"] == "passed"
    assert report["preflight"]["passed_count"] == 2
    assert report["preflight"]["blocked_count"] == 0

    refute Enum.any?(report["blockers"], &(&1["code"] == "provider_preflight_report_required"))
    refute Enum.any?(report["blockers"], &(&1["code"] == "provider_preflight_blocked"))
    assert Enum.any?(report["blockers"], &(&1["code"] == "completed_evidence_packet_required"))
  end

  test "reports invalid preflight metadata without echoing normalized artifacts" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_cnb_shadow)
    invalid_preflight = Map.put(preflight_report(phase2_plan, "passed"), "provider_preflight_results", [])

    assert {:ok, report} = StatusReport.build(phase2_plan, preflight_report: invalid_preflight)

    assert report["status"] == "blocked"
    assert report["preflight"]["provided"] == true
    assert report["preflight"]["valid"] == false
    assert report["normalized_artifacts_included"] == false

    assert [%{"code" => "provider_preflight_report_invalid", "error_count" => error_count}] =
             Enum.filter(report["blockers"], &(&1["code"] == "provider_preflight_report_invalid"))

    assert error_count > 0
    refute Enum.any?(report["blockers"], &(&1["code"] == "provider_preflight_report_required"))
  end

  test "exposes status reports through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_profile_status.v1"}} =
             ProductionProfile.production_status(:linear_cnb_shadow)
  end

  defp preflight_report(phase2_plan, status) do
    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => preflight_results(phase2_plan, status),
      "explicit_non_claims" => ["preflight_report_does_not_enable_production"]
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
    base_result(provider_plan, command)
    |> Map.merge(%{
      "status" => "passed",
      "evidence_files" => ["evidence/preflight/#{Map.fetch!(command, "id")}.md"],
      "missing_prerequisites" => []
    })
  end

  defp preflight_result(provider_plan, command, "blocked") do
    base_result(provider_plan, command)
    |> Map.merge(%{
      "status" => "blocked",
      "blocker_code" => "missing_prerequisites",
      "missing_prerequisites" => [first_prerequisite(command)]
    })
  end

  defp base_result(provider_plan, command) do
    %{
      "template" => Map.fetch!(provider_plan, "template"),
      "command_id" => Map.fetch!(command, "id"),
      "target" => Map.fetch!(command, "target"),
      "provider_kind" => Map.fetch!(command, "provider_kind"),
      "ran_at" => "2026-06-26T00:00:00Z",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false
    }
  end

  defp first_prerequisite(command) do
    command
    |> Map.take(["required_env", "required_auth", "required_targets", "required_runtime"])
    |> Map.values()
    |> Enum.find_value(fn
      [value | _rest] -> value
      _empty -> nil
    end)
  end
end
