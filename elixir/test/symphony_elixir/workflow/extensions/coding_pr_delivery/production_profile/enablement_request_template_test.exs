defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequestTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequest
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequestTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacketTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewDecision
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacketTemplate
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "builds an enablement request template from a ready review decision" do
    decision = ready_review_decision()

    assert {:ok, template} =
             EnablementRequestTemplate.build(decision,
               provider_matrix_entry_ids: ["tapd-cnb-shadow"],
               repositories: ["acme/widgets"]
             )

    assert template["schema"] == "coding_pr_delivery.production_enablement_request_template.v1"
    assert template["completed_packet_schema"] == "coding_pr_delivery.production_enablement_request.v1"
    assert template["template_authority"] == "enablement_request_shape_only"
    assert template["does_not_enable_production"] == true

    field_template = template["enablement_request_field_template"]

    assert field_template["scope"] == %{
             "environment" => "production",
             "repositories" => ["acme/widgets"],
             "provider_matrix_entry_ids" => ["tapd-cnb-shadow"],
             "side_effect_mode" => "shadow_no_write"
           }

    assert field_template["gate_values"][Gates.transition_readiness_required_gate_key()] == false
    assert field_template["activation_control"]["requires_operator_apply"] == true
    assert field_template["activation_control"]["applies_immediately"] == false
    assert "multi_node_ownership" in field_template["acknowledged_non_claims"]
  end

  test "field template can be completed into a valid enablement request" do
    decision = ready_review_decision()

    assert {:ok, template} =
             EnablementRequestTemplate.build(decision,
               provider_matrix_entry_ids: ["tapd-cnb-shadow"],
               repositories: ["acme/widgets"]
             )

    enablement_request =
      template["enablement_request_field_template"]
      |> Map.merge(%{
        "enablement_request_id" => "enablement-tapd-cnb-shadow",
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

    assert {:ok, %{"schema" => "coding_pr_delivery.production_enablement_request.v1"}} =
             EnablementRequest.validate(enablement_request)
  end

  test "builds a Linear + CNB shadow enablement request template from a ready review decision" do
    decision = ready_review_decision(:linear_cnb_shadow, "shadow-run-linear-cnb-42")

    assert {:ok, template} =
             EnablementRequestTemplate.build(decision,
               provider_matrix_entry_ids: ["linear-cnb-shadow"],
               repositories: ["acme/widgets"]
             )

    field_template = template["enablement_request_field_template"]

    assert template["does_not_enable_production"] == true

    assert template["selected_provider_entries"] == [
             %{
               "entry_id" => "linear-cnb-shadow",
               "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
               "tracker" => %{"kind" => "linear"},
               "repo_provider" => %{"kind" => "cnb"},
               "agent_provider" => %{"kind" => "configured_agent_provider"},
               "side_effect_mode" => "shadow_no_write",
               "topology_mode" => "singleton",
               "non_claims" => [
                 "multi_node_ownership",
                 "automatic_durable_replay",
                 "automatic_cold_start_provider_rebuild"
               ]
             }
           ]

    assert field_template["scope"] == %{
             "environment" => "production",
             "repositories" => ["acme/widgets"],
             "provider_matrix_entry_ids" => ["linear-cnb-shadow"],
             "side_effect_mode" => "shadow_no_write"
           }

    assert field_template["gate_values"][Gates.transition_readiness_required_gate_key()] == false
    assert field_template["activation_control"]["requires_operator_apply"] == true
    assert field_template["activation_control"]["applies_immediately"] == false
    assert "multi_node_ownership" in field_template["acknowledged_non_claims"]
  end

  test "marks ready-to-land templates with transition readiness required" do
    decision =
      ready_review_decision()
      |> Map.put("provider_entries", [
        %{
          "entry_id" => "linear-github-ready",
          "tracker" => %{"kind" => "linear"},
          "repo_provider" => %{"kind" => "github"},
          "agent_provider" => %{"kind" => "codex"},
          "side_effect_mode" => "ready_to_land_write",
          "topology_mode" => "singleton",
          "non_claims" => ["multi_node_ownership"]
        }
      ])

    assert {:ok, template} =
             EnablementRequestTemplate.build(decision, provider_matrix_entry_ids: ["linear-github-ready"])

    field_template = template["enablement_request_field_template"]

    assert field_template["scope"]["side_effect_mode"] == "ready_to_land_write"
    assert field_template["gate_values"][Gates.transition_readiness_required_gate_key()] == true
  end

  test "rejects blocked review decisions and mixed provider modes" do
    blocked =
      ready_review_decision()
      |> Map.put("status", "blocked")
      |> Map.put("blockers", [%{"code" => "missing_evidence"}])

    assert {:error, %{errors: errors}} = EnablementRequestTemplate.build(blocked)

    assert Enum.any?(errors, &(&1.code == "review_decision_not_ready"))
    assert Enum.any?(errors, &(&1.code == "review_decision_blocked"))

    mixed =
      ready_review_decision()
      |> Map.put("provider_entries", [
        %{"entry_id" => "tapd-cnb-shadow", "side_effect_mode" => "shadow_no_write", "non_claims" => []},
        %{"entry_id" => "linear-github-ready", "side_effect_mode" => "ready_to_land_write", "non_claims" => []}
      ])

    assert {:error, %{errors: mixed_errors}} =
             EnablementRequestTemplate.build(mixed, side_effect_mode: "shadow_no_write")

    assert Enum.any?(mixed_errors, &(&1.code == "mixed_side_effect_modes"))
  end

  test "exposes enablement templates through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_enablement_request_template.v1"}} =
             ProductionProfile.enablement_request_template(ready_review_decision(),
               provider_matrix_entry_ids: ["tapd-cnb-shadow"],
               repositories: ["acme/widgets"]
             )
  end

  defp ready_review_decision(template \\ :tapd_cnb_shadow, shadow_run_id \\ "shadow-run-cnb-42") do
    entry_id = entry_id(template)

    assert {:ok, review_packet_template} =
             ReviewPacketTemplate.build(completed_evidence_packet(template, shadow_run_id))

    review_packet =
      complete_review_packet(review_packet_template["review_packet_field_template"], entry_id, template, shadow_run_id)

    assert {:ok, decision} = ReviewDecision.build(review_packet)
    decision
  end

  defp complete_review_packet(field_template, entry_id, template, shadow_run_id) do
    field_template
    |> Map.merge(%{
      "review_packet_id" => "review-packet-#{entry_id}",
      "changed_source_specs" => [
        "specs/workflow/profiles/coding_pr_delivery/profile_spec.md",
        "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md"
      ],
      "implementation_refs" => [
        "commit:27fad4c",
        "local-patch:coding-pr-delivery-enable-template"
      ],
      "deterministic_test_matrix" => [
        %{"command" => "mise exec -- mix test test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile", "status" => "passed"}
      ],
      "provider_preflight_reports" => [passed_preflight_report(template, shadow_run_id)],
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

  defp passed_preflight_report(:tapd_cnb_shadow, shadow_run_id) do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:tapd_cnb_shadow, tapd_cnb_shadow_run_id: shadow_run_id)
    preflight_report(phase2_plan)
  end

  defp passed_preflight_report(:linear_cnb_shadow, shadow_run_id) do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: shadow_run_id)
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
