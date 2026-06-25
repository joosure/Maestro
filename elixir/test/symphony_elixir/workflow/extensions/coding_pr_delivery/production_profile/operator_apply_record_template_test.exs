defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecordTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequestTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacketTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyPlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecord
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecordTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewDecision
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacketTemplate
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "builds an operator apply-record template from a ready apply plan" do
    assert {:ok, apply_plan} = ready_apply_plan()
    assert {:ok, template} = OperatorApplyRecordTemplate.build(apply_plan)

    assert template["schema"] == "coding_pr_delivery.production_operator_apply_record_template.v1"
    assert template["completed_packet_schema"] == "coding_pr_delivery.production_operator_apply_record.v1"
    assert template["template_authority"] == "operator_apply_record_shape_only"
    assert template["does_not_apply_settings"] == true

    field_template = template["apply_record_field_template"]

    assert field_template["operator_apply_plan"] == apply_plan
    assert field_template["apply_metadata"]["change_ticket"] == "CHANGE-123"
    assert field_template["apply_metadata"]["operator_confirmation"] == true
    assert field_template["apply_metadata"]["automatic_apply"] == false
    assert field_template["applied_scope"] == apply_plan["scope"]
    assert field_template["applied_gate_values"] == apply_plan["gate_values"]
    assert field_template["rollback_readiness"]["verified"] == false
    assert field_template["observation_start"]["started"] == false
    assert Gates.transition_readiness_required_gate_key() in field_template["rollback_readiness"]["disable_gates"]
  end

  test "field template can be completed into a valid operator apply record" do
    assert {:ok, apply_plan} = ready_apply_plan()
    assert {:ok, template} = OperatorApplyRecordTemplate.build(apply_plan)

    record =
      template["apply_record_field_template"]
      |> Map.merge(%{"apply_record_id" => "apply-record-tapd-cnb-shadow"})
      |> put_in(["apply_metadata", "applied_by"], "release-operator")
      |> put_in(["apply_metadata", "applied_at"], "2026-06-25T00:30:00Z")
      |> put_in(["rollback_readiness", "verified"], true)
      |> put_in(["observation_start", "started"], true)
      |> Map.update!("completed_operator_steps", fn steps ->
        Enum.map(steps, fn step ->
          step
          |> Map.put("completed_by", "release-operator")
          |> Map.put("completed_at", "2026-06-25T00:30:00Z")
        end)
      end)

    assert {:ok, %{"schema" => "coding_pr_delivery.production_operator_apply_record.v1"}} =
             OperatorApplyRecord.validate(record)
  end

  test "builds a Linear + CNB shadow operator apply-record template from a ready apply plan" do
    assert {:ok, apply_plan} = ready_apply_plan(:linear_cnb_shadow, "shadow-run-linear-cnb-42")
    assert {:ok, template} = OperatorApplyRecordTemplate.build(apply_plan)

    field_template = template["apply_record_field_template"]

    assert template["schema"] == "coding_pr_delivery.production_operator_apply_record_template.v1"
    assert template["does_not_apply_settings"] == true
    assert field_template["operator_apply_plan"] == apply_plan

    assert field_template["applied_scope"] == %{
             "environment" => "production",
             "repositories" => ["acme/widgets"],
             "provider_matrix_entry_ids" => ["linear-cnb-shadow"],
             "side_effect_mode" => "shadow_no_write"
           }

    assert field_template["applied_gate_values"][Gates.transition_readiness_required_gate_key()] == false
    assert field_template["apply_metadata"]["operator_confirmation"] == true
    assert field_template["apply_metadata"]["automatic_apply"] == false
    assert field_template["rollback_readiness"]["verified"] == false
    assert Gates.transition_readiness_required_gate_key() in field_template["rollback_readiness"]["disable_gates"]
    assert field_template["observation_start"]["started"] == false
    assert field_template["observation_start"]["observation_window"] == apply_plan["observation_window"]
  end

  test "rejects blocked apply plans before building a record template" do
    {:ok, blocked_plan} = OperatorApplyPlan.build(%{})

    assert {:error, %{code: "coding_pr_delivery_operator_apply_record_template_invalid", errors: errors}} =
             OperatorApplyRecordTemplate.build(blocked_plan)

    assert Enum.any?(errors, &(&1.code == "operator_apply_plan_not_ready"))
    assert Enum.any?(errors, &(&1.code == "operator_apply_plan_blocked"))
  end

  test "exposes operator apply-record templates through the production profile facade" do
    assert {:ok, apply_plan} = ready_apply_plan()

    assert {:ok, %{"schema" => "coding_pr_delivery.production_operator_apply_record_template.v1"}} =
             ProductionProfile.operator_apply_record_template(apply_plan)
  end

  defp ready_apply_plan(template \\ :tapd_cnb_shadow, shadow_run_id \\ "shadow-run-cnb-42") do
    entry_id = entry_id(template)

    assert {:ok, enablement_template} =
             EnablementRequestTemplate.build(ready_review_decision(template, shadow_run_id),
               provider_matrix_entry_ids: [entry_id],
               repositories: ["acme/widgets"]
             )

    enablement_request =
      enablement_template["enablement_request_field_template"]
      |> Map.merge(%{
        "enablement_request_id" => "enablement-#{entry_id}",
        "requested_by" => "release-manager",
        "requested_at" => "2026-06-25T00:00:00Z",
        "approvals" => [
          %{
            "role" => "workflow-runtime-owner",
            "owner" => "workflow-runtime",
            "decision" => "approved",
            "approved_at" => "2026-06-25T00:00:00Z"
          }
        ]
      })
      |> put_in(["activation_control", "change_ticket"], "CHANGE-123")

    OperatorApplyPlan.build(enablement_request)
  end

  defp ready_review_decision(template, shadow_run_id) do
    entry_id = entry_id(template)

    assert {:ok, review_packet_template} =
             ReviewPacketTemplate.build(completed_evidence_packet(template, shadow_run_id))

    review_packet = complete_review_packet(review_packet_template["review_packet_field_template"], entry_id)

    assert {:ok, decision} = ReviewDecision.build(review_packet)
    decision
  end

  defp complete_review_packet(field_template, entry_id) do
    field_template
    |> Map.merge(%{
      "review_packet_id" => "review-packet-#{entry_id}",
      "changed_source_specs" => [
        "specs/workflow/profiles/coding_pr_delivery/profile_spec.md",
        "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md"
      ],
      "implementation_refs" => [
        "commit:27fad4c",
        "local-patch:coding-pr-delivery-apply-record-template"
      ],
      "deterministic_test_matrix" => [
        %{"command" => "mise exec -- mix test test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile", "status" => "passed"}
      ],
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
  end

  defp completed_evidence_packet(template, shadow_run_id) do
    assert {:ok, claim} = Phase2ClaimTemplate.build(template, shadow_run_id: shadow_run_id)
    assert {:ok, template} = EvidencePacketTemplate.build(claim)

    %{
      "production_claim" => claim,
      "scenario_evidence" => Enum.map(template["scenario_evidence_requirements"], &complete_scenario_evidence/1),
      "non_claim_acknowledgements" => Enum.map(template["non_claim_acknowledgement_requirements"], &complete_non_claim_acknowledgement/1)
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

  defp entry_id(:tapd_cnb_shadow), do: "tapd-cnb-shadow"
  defp entry_id(:linear_cnb_shadow), do: "linear-cnb-shadow"
end
