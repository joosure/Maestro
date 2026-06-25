defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacketTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacketTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacket
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacketTemplate
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  test "builds a Phase 4 review-packet fill template from completed evidence" do
    assert {:ok, template} = ReviewPacketTemplate.build(completed_evidence_packet())

    assert template["schema"] == "coding_pr_delivery.production_review_packet_template.v1"
    assert template["completed_packet_schema"] == "coding_pr_delivery.production_review_packet.v1"
    assert template["template_authority"] == "review_packet_shape_only"
    assert template["does_not_read_evidence_files"] == true

    field_template = template["review_packet_field_template"]

    assert field_template["rollback_instructions"]["external_transition_readiness_gate"] ==
             Gates.transition_readiness_required_gate_key()

    assert field_template["rollback_instructions"]["legacy_review_handoff_required_mapping"] == true
    assert "review_packet_render" in field_template["scrubbing_pipeline"]["enforced_boundaries"]
    assert field_template["scrubbing_pipeline"]["pattern_catalog_rules"] == Governance.required_scrubbing_pattern_rules()
    assert field_template["operator_inspection"]["contains_raw_evidence_payload"] == false
    assert field_template["provider_preflight_reports"] == []
    assert field_template["authority_boundaries"]["raw_provider_passthrough_authorized"] == false
    assert "provider_preflight_reports" in template["fields_to_complete"]
    assert "owner_signoffs" in template["fields_to_complete"]
  end

  test "field template can be completed into a valid review packet" do
    assert {:ok, template} = ReviewPacketTemplate.build(completed_evidence_packet())

    review_packet =
      template["review_packet_field_template"]
      |> Map.merge(%{
        "review_packet_id" => "review-packet-tapd-cnb-shadow",
        "changed_source_specs" => [
          "specs/workflow/profiles/coding_pr_delivery/profile_spec.md",
          "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md"
        ],
        "implementation_refs" => [
          "commit:27fad4c",
          "local-patch:coding-pr-delivery-review-packet-template"
        ],
        "deterministic_test_matrix" => [
          %{"command" => "mise exec -- mix test test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile", "status" => "passed"}
        ],
        "provider_preflight_reports" => [passed_preflight_report(:tapd_cnb_shadow, "shadow-run-cnb-42")],
        "owner_signoffs" => [
          %{
            "role" => "workflow-runtime-owner",
            "owner" => "workflow-runtime",
            "decision" => "approved",
            "approved_at" => "2026-06-25T00:00:00Z"
          }
        ]
      })
      |> put_in(["scrubbing_pipeline", "test_results"], [
        %{"name" => "scrubber evidence boundaries", "status" => "passed"}
      ])

    assert {:ok, %{"schema" => "coding_pr_delivery.production_review_packet.v1"}} =
             ReviewPacket.validate(review_packet)
  end

  test "builds a Linear + CNB shadow review template with bounded operator inspection" do
    assert {:ok, template} =
             ReviewPacketTemplate.build(completed_evidence_packet(:linear_cnb_shadow, "shadow-run-linear-cnb-42"))

    field_template = template["review_packet_field_template"]
    inspection = field_template["operator_inspection"]

    assert template["does_not_read_evidence_files"] == true
    assert inspection["contains_raw_evidence_payload"] == false
    assert inspection["workpad_markdown_authoritative"] == false
    assert inspection["gate_values"][Gates.transition_readiness_required_gate_key()] == false

    assert [
             %{
               "provider_matrix_entry_id" => "linear-cnb-shadow",
               "gate_values" => linear_cnb_gates
             }
           ] = inspection["candidate_gate_values_by_entry"]

    assert linear_cnb_gates[Gates.transition_readiness_required_gate_key()] == false
    assert field_template["scrubbing_pipeline"]["source_provider_matrix_entry_ids"] == ["linear-cnb-shadow"]
    assert field_template["retention_policy"]["source_provider_matrix_entry_ids"] == ["linear-cnb-shadow"]
    assert field_template["authority_boundaries"]["raw_provider_passthrough_authorized"] == false
  end

  test "rejects invalid evidence packets before building a review template" do
    assert {:error, %{code: "coding_pr_delivery_evidence_packet_invalid", errors: errors}} =
             ReviewPacketTemplate.build(%{})

    assert Enum.any?(errors, &(&1.code == "invalid_type" and &1.path == ["production_claim"]))
  end

  test "exposes review packet templates through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_review_packet_template.v1"}} =
             ProductionProfile.phase4_review_packet_template(completed_evidence_packet())
  end

  defp completed_evidence_packet(template \\ :tapd_cnb_shadow, shadow_run_id \\ "shadow-run-cnb-42") do
    assert {:ok, claim} = Phase2ClaimTemplate.build(template, shadow_run_id: shadow_run_id)
    assert {:ok, template} = EvidencePacketTemplate.build(claim)

    %{
      "production_claim" => claim,
      "scenario_evidence" => Enum.map(template["scenario_evidence_requirements"], &complete_scenario_evidence/1),
      "non_claim_acknowledgements" => Enum.map(template["non_claim_acknowledgement_requirements"], &complete_non_claim_acknowledgement/1)
    }
  end

  defp passed_preflight_report(:tapd_cnb_shadow, shadow_run_id) do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:tapd_cnb_shadow, tapd_cnb_shadow_run_id: shadow_run_id)
    preflight_report(phase2_plan)
  end

  defp preflight_report(phase2_plan) do
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
      |> Enum.map(&preflight_result(template, &1))
    end)
  end

  defp preflight_result(template, command) do
    %{
      "template" => template,
      "command_id" => Map.fetch!(command, "id"),
      "target" => Map.fetch!(command, "target"),
      "provider_kind" => Map.fetch!(command, "provider_kind"),
      "status" => "passed",
      "ran_at" => "2026-06-25T00:00:00Z",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false,
      "evidence_files" => ["evidence/preflight/#{template}/#{Map.fetch!(command, "id")}.md"]
    }
  end

  defp complete_scenario_evidence(requirement) do
    evidence =
      %{
        "provider_matrix_entry_id" => requirement["provider_matrix_entry_id"],
        "scenario_id" => requirement["scenario_id"],
        "status" => requirement["required_status"],
        "evidence_kind" => requirement["required_evidence_kind"],
        "collector" => "provider-integration-owner",
        "collected_at" => "2026-06-25T00:00:00Z",
        "evidence_files" => requirement["evidence_files"]
      }

    if is_map(requirement["shadow"]) do
      evidence
      |> Map.merge(requirement["no_write_flags"])
      |> Map.put("shadow", requirement["shadow"])
    else
      evidence
    end
  end

  defp complete_non_claim_acknowledgement(requirement) do
    %{
      "provider_matrix_entry_id" => requirement["provider_matrix_entry_id"],
      "non_claims" => requirement["non_claims"],
      "owner" => "provider-integration-owner",
      "acknowledged_at" => "2026-06-25T00:00:00Z"
    }
  end
end
