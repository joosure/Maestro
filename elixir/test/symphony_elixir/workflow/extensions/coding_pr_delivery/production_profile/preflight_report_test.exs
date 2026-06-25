defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReportTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReport

  test "validates a blocked read-only preflight report without raw output" do
    report = blocked_report()

    assert {:ok, normalized} = PreflightReport.validate(report)

    assert normalized["schema"] == "coding_pr_delivery.provider_preflight_report.v1"
    assert normalized["status"] == "blocked"
    assert normalized["planned_preflight_command_count"] == 6
    assert normalized["preflight_result_count"] == 6
    assert normalized["raw_output_included"] == false
    assert normalized["does_not_call_providers"] == true
    assert normalized["does_not_enable_production"] == true
  end

  test "requires every planned read-only preflight command exactly once" do
    report =
      blocked_report()
      |> update_in(["provider_preflight_results"], &tl/1)

    assert {:error, %{errors: errors}} = PreflightReport.validate(report)

    assert Enum.any?(errors, &(&1.code == "missing_preflight_result"))
  end

  test "requires the preflight report schema" do
    report = Map.delete(blocked_report(), "schema")

    assert {:error, %{errors: errors}} = PreflightReport.validate(report)

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["schema"]))
  end

  test "rejects unknown missing prerequisites and raw preflight output" do
    report =
      blocked_report()
      |> update_in(["provider_preflight_results", Access.at(0)], fn result ->
        result
        |> Map.put("missing_prerequisites", ["UNDECLARED_SECRET"])
        |> Map.put("stdout", "raw provider output")
      end)

    assert {:error, %{errors: errors}} = PreflightReport.validate(report)

    assert Enum.any?(errors, &(&1.code == "unknown_preflight_prerequisite"))
    assert Enum.any?(errors, &(&1.code == "raw_preflight_output_forbidden" and &1.path == ["provider_preflight_results", 0, "stdout"]))
  end

  test "rejects preflight reports that claim writes or production enablement" do
    report =
      blocked_report()
      |> put_in(["provider_preflight_results", Access.at(0), "write_performed"], true)
      |> put_in(["provider_preflight_results", Access.at(1), "production_enabled"], true)

    assert {:error, %{errors: errors}} = PreflightReport.validate(report)

    assert Enum.any?(errors, &(&1.code == "preflight_write_performed"))
    assert Enum.any?(errors, &(&1.code == "preflight_enabled_production"))
  end

  test "exposes preflight report validation through the production profile facade" do
    assert {:ok, %{"status" => "blocked"}} = ProductionProfile.validate_preflight_report(blocked_report())
  end

  defp blocked_report do
    assert {:ok, phase2_plan} =
             Phase2EvidencePlan.build(:tiered_reference,
               tapd_cnb_shadow_run_id: "preflight-tapd-cnb",
               linear_cnb_shadow_run_id: "preflight-linear-cnb"
             )

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
      template = Map.fetch!(provider_plan, "template")

      provider_plan
      |> get_in(["read_only_preflight", "commands"])
      |> Enum.map(&blocked_result(template, &1))
    end)
  end

  defp blocked_result(template, command) do
    %{
      "template" => template,
      "command_id" => Map.fetch!(command, "id"),
      "target" => Map.fetch!(command, "target"),
      "provider_kind" => Map.fetch!(command, "provider_kind"),
      "status" => "blocked",
      "blocker_code" => "missing_preflight_prerequisite",
      "missing_prerequisites" => [first_prerequisite(command)],
      "ran_at" => "2026-06-26T03:10:00Z",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false
    }
  end

  defp first_prerequisite(command) do
    command
    |> Map.take(["required_env", "required_auth", "required_targets"])
    |> Map.values()
    |> Enum.flat_map(fn
      values when is_list(values) -> values
      _value -> []
    end)
    |> List.first()
  end
end
