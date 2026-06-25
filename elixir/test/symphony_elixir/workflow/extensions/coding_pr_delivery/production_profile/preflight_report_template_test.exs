defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReportTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    Phase2EvidencePlan,
    PreflightReport,
    PreflightReportTemplate
  }

  test "builds bounded preflight report templates from Phase 2 evidence plans" do
    assert {:ok, phase2_plan} =
             Phase2EvidencePlan.build(:tiered_reference,
               tapd_cnb_shadow_run_id: "template-tapd-cnb",
               linear_cnb_shadow_run_id: "template-linear-cnb"
             )

    phase2_plan = Map.put(phase2_plan, "raw_payload", "raw phase2 input")

    assert {:ok, template} = PreflightReportTemplate.build(phase2_plan)

    assert template["schema"] == "coding_pr_delivery.provider_preflight_report_template.v1"
    assert template["completed_packet_schema"] == "coding_pr_delivery.provider_preflight_report.v1"
    assert template["template_authority"] == "preflight_report_shape_only"
    assert template["does_not_collect_live_evidence"] == true
    assert template["does_not_call_providers"] == true
    assert template["does_not_enable_production"] == true

    requirements = template["preflight_result_requirements"]
    assert length(requirements) == 6
    assert Enum.all?(requirements, &(&1["raw_output_allowed"] == false))
    assert Enum.all?(requirements, &(&1["required_side_effect_mode"] == "read_only"))
    assert Enum.all?(requirements, &(&1["write_performed"] == false))
    assert Enum.all?(requirements, &(&1["production_enabled"] == false))
    assert Enum.all?(requirements, &(&1["allowed_evidence_ref_prefixes"] == ["evidence/", "https://", "http://"]))
    assert Enum.all?(requirements, &(List.first(&1["evidence_files"]) =~ "evidence/preflight/"))

    field_template = template["preflight_report_field_template"]
    refute Map.has_key?(field_template["phase2_evidence_plan"], "raw_payload")
    assert length(field_template["provider_preflight_results"]) == 6
  end

  test "generated field templates can be completed into valid preflight reports" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_cnb_shadow)
    assert {:ok, template} = PreflightReportTemplate.build(phase2_plan)

    report =
      template["preflight_report_field_template"]
      |> Map.put("provider_preflight_results", completed_results(template))

    assert {:ok, normalized} = PreflightReport.validate(report)

    assert normalized["schema"] == "coding_pr_delivery.provider_preflight_report.v1"
    assert normalized["status"] == "passed"
    assert normalized["planned_preflight_command_count"] == 2
    assert normalized["raw_output_included"] == false
    assert normalized["does_not_call_providers"] == true
    assert normalized["does_not_enable_production"] == true
  end

  test "rejects invalid Phase 2 evidence plans" do
    assert {:error, %{code: "coding_pr_delivery_preflight_report_template_invalid", errors: errors}} =
             PreflightReportTemplate.build(%{"schema" => "wrong"})

    assert Enum.any?(errors, &(&1.code == "invalid_phase2_schema"))
    assert Enum.any?(errors, &(&1.code == "missing_provider_plans"))
  end

  test "exposes preflight report templates through the production profile facade" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:tapd_cnb_shadow)

    assert {:ok, %{"schema" => "coding_pr_delivery.provider_preflight_report_template.v1"}} =
             ProductionProfile.phase2_preflight_report_template(phase2_plan)
  end

  defp completed_results(template) do
    Enum.map(template["preflight_result_requirements"], fn requirement ->
      %{
        "template" => requirement["template"],
        "command_id" => requirement["command_id"],
        "target" => requirement["target"],
        "provider_kind" => requirement["provider_kind"],
        "status" => "passed",
        "ran_at" => "2026-06-26T04:30:00Z",
        "side_effect_mode" => "read_only",
        "write_performed" => false,
        "production_enabled" => false,
        "evidence_files" => requirement["evidence_files"]
      }
    end)
  end
end
