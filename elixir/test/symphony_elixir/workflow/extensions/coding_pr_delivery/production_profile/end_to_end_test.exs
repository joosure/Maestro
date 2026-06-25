defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EndToEndTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @timestamp "2026-06-25T00:00:00Z"

  test "TAPD and CNB shadow template chain reaches observation decision without production writes" do
    assert_shadow_chain(:tapd_cnb_shadow, "tapd-cnb-shadow", "tapd", "shadow-run-cnb-42")
  end

  test "Linear and CNB shadow template chain reaches observation decision without production writes" do
    assert_shadow_chain(:linear_cnb_shadow, "linear-cnb-shadow", "linear", "shadow-run-linear-cnb-42")
  end

  defp assert_shadow_chain(template, entry_id, tracker_kind, shadow_run_id) do
    assert {:ok, claim} =
             ProductionProfile.phase2_claim_template(template, shadow_run_id: shadow_run_id)

    assert [
             %{
               "id" => ^entry_id,
               "tracker" => %{"kind" => ^tracker_kind},
               "repo_provider" => %{"kind" => "cnb"},
               "side_effect_mode" => "shadow_no_write",
               "shadow" => shadow
             }
           ] = claim["provider_matrix"]

    assert shadow["prefix"] == OneShotContract.shadow_prefix()
    assert shadow["authority"] == OneShotContract.shadow_authority()
    assert shadow["canonical_authority"] == false
    assert shadow["run_id"] == shadow_run_id

    assert {:ok, evidence_template} = ProductionProfile.phase2_evidence_packet_template(claim)
    assert evidence_template["does_not_collect_live_evidence"] == true
    assert Enum.all?(evidence_template["scenario_evidence_requirements"], &shadow_requirement?/1)

    evidence_packet = complete_evidence_packet(evidence_template)
    assert {:ok, evidence_packet} = ProductionProfile.validate_evidence_packet(evidence_packet)

    assert {:ok, review_template} = ProductionProfile.phase4_review_packet_template(evidence_packet)
    assert review_template["does_not_read_evidence_files"] == true

    review_packet = complete_review_packet(review_template, entry_id, template, shadow_run_id)
    assert {:ok, review_packet} = ProductionProfile.validate_review_packet(review_packet)
    assert review_packet["scrubbing_pipeline"]["failure_behavior"] == "fail_closed"
    assert review_packet["retention_policy"]["tombstone_preserving"] == true

    assert {:ok, review_decision} = ProductionProfile.review_decision(review_packet)
    assert review_decision["status"] == "ready_for_approval"
    assert review_decision["does_not_enable_production"] == true
    assert review_decision["raw_evidence_payload_included"] == false

    assert {:ok, enablement_template} =
             ProductionProfile.enablement_request_template(review_decision,
               provider_matrix_entry_ids: [entry_id],
               repositories: ["acme/widgets"]
             )

    assert enablement_template["does_not_enable_production"] == true

    enablement_request = complete_enablement_request(enablement_template, entry_id)

    assert {:ok, normalized_enablement_request} =
             ProductionProfile.validate_enablement_request(enablement_request)

    assert normalized_enablement_request["gate_values"][Gates.transition_readiness_required_gate_key()] ==
             false

    assert {:ok, apply_plan} = ProductionProfile.operator_apply_plan(enablement_request)
    assert apply_plan["status"] == "ready_for_operator_apply"
    assert apply_plan["does_not_apply_settings"] == true
    assert apply_plan["can_apply_automatically"] == false

    assert {:ok, apply_record_template} = ProductionProfile.operator_apply_record_template(apply_plan)
    assert apply_record_template["does_not_apply_settings"] == true

    apply_record = complete_apply_record(apply_record_template, entry_id)

    assert {:ok, normalized_apply_record} =
             ProductionProfile.validate_operator_apply_record(apply_record)

    assert normalized_apply_record["records_external_operator_apply"] == true

    assert {:ok, observation_template} = ProductionProfile.observation_status_template(apply_record)
    assert observation_template["records_observation_only"] == true
    assert observation_template["does_not_enable_production"] == true

    observation_status = complete_observation_status(observation_template, entry_id)

    assert {:ok, normalized_observation_status} =
             ProductionProfile.validate_observation_status(observation_status)

    assert normalized_observation_status["no_write_observation"] == %{
             "production_write_performed" => false,
             "canonical_surface_mutated" => false
           }

    assert {:ok, observation_decision} = ProductionProfile.observation_decision(observation_status)
    assert observation_decision["status"] == "observation_passed"
    assert observation_decision["records_observation_only"] == true
    assert observation_decision["does_not_enable_production"] == true
    assert observation_decision["raw_evidence_payload_included"] == false
  end

  defp shadow_requirement?(requirement) do
    no_write_flags = requirement["no_write_flags"]
    shadow = requirement["shadow"]

    requirement["required_evidence_kind"] == "shadow_integration" and
      no_write_flags["production_write_performed"] == false and
      no_write_flags["canonical_surface_mutated"] == false and
      shadow["prefix"] == OneShotContract.shadow_prefix() and
      shadow["authority"] == OneShotContract.shadow_authority() and
      shadow["canonical_authority"] == false and
      shadow["allowed_destinations"] == OneShotContract.shadow_allowed_destinations()
  end

  defp complete_evidence_packet(template) do
    %{
      "production_claim" => template["production_claim"],
      "scenario_evidence" => Enum.map(template["scenario_evidence_requirements"], &complete_scenario_evidence/1),
      "non_claim_acknowledgements" =>
        Enum.map(
          template["non_claim_acknowledgement_requirements"],
          &complete_non_claim_acknowledgement/1
        )
    }
  end

  defp complete_scenario_evidence(requirement) do
    %{
      "provider_matrix_entry_id" => requirement["provider_matrix_entry_id"],
      "scenario_id" => requirement["scenario_id"],
      "status" => requirement["required_status"],
      "evidence_kind" => requirement["required_evidence_kind"],
      "collector" => "provider-integration-owner",
      "collected_at" => @timestamp,
      "evidence_files" => requirement["evidence_files"],
      "shadow" => requirement["shadow"],
      "production_write_performed" => false,
      "canonical_surface_mutated" => false
    }
  end

  defp complete_non_claim_acknowledgement(requirement) do
    %{
      "provider_matrix_entry_id" => requirement["provider_matrix_entry_id"],
      "non_claims" => requirement["non_claims"],
      "owner" => "provider-integration-owner",
      "acknowledged_at" => @timestamp
    }
  end

  defp complete_review_packet(template, entry_id, plan_template, shadow_run_id) do
    template["review_packet_field_template"]
    |> Map.merge(%{
      "review_packet_id" => "review-packet-#{entry_id}",
      "changed_source_specs" => [
        "specs/workflow/profiles/coding_pr_delivery/production_hardening_plan.md",
        "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md"
      ],
      "implementation_refs" => ["commit:production-profile-#{entry_id}-shadow-chain"],
      "deterministic_test_matrix" => [
        %{
          "command" => "mise exec -- mix test test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile",
          "status" => "passed"
        }
      ],
      "provider_preflight_reports" => [passed_preflight_report(plan_template, shadow_run_id)],
      "owner_signoffs" => [
        %{
          "role" => "workflow-runtime-owner",
          "owner" => "workflow-runtime",
          "decision" => "approved",
          "approved_at" => @timestamp
        }
      ]
    })
    |> put_in(["scrubbing_pipeline", "test_results"], [
      %{"name" => "scrubber evidence write and render boundaries", "status" => "passed"}
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
      "ran_at" => @timestamp,
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false
    }
  end

  defp complete_enablement_request(template, entry_id) do
    template["enablement_request_field_template"]
    |> Map.merge(%{
      "enablement_request_id" => "enablement-#{entry_id}",
      "requested_by" => "release-manager",
      "requested_at" => @timestamp,
      "approvals" => [
        %{
          "role" => "workflow-runtime-owner",
          "owner" => "workflow-runtime",
          "decision" => "approved",
          "approved_at" => @timestamp
        }
      ]
    })
    |> put_in(["activation_control", "change_ticket"], "CHANGE-123")
  end

  defp complete_apply_record(template, entry_id) do
    template["apply_record_field_template"]
    |> Map.merge(%{"apply_record_id" => "apply-record-#{entry_id}"})
    |> put_in(["apply_metadata", "applied_by"], "release-operator")
    |> put_in(["apply_metadata", "applied_at"], @timestamp)
    |> put_in(["rollback_readiness", "verified"], true)
    |> put_in(["observation_start", "started"], true)
    |> Map.update!("completed_operator_steps", fn steps ->
      Enum.map(steps, fn step ->
        step
        |> Map.put("completed_by", "release-operator")
        |> Map.put("completed_at", @timestamp)
      end)
    end)
  end

  defp complete_observation_status(template, entry_id) do
    template["observation_status_field_template"]
    |> Map.merge(%{
      "observation_status_id" => "observation-#{entry_id}",
      "observed_by" => "release-operator",
      "observed_at" => @timestamp,
      "status" => "passed"
    })
    |> Map.update!("criteria_results", fn results ->
      Enum.map(results, fn result ->
        result
        |> Map.put("status", "passed")
        |> Map.put("observed_at", @timestamp)
        |> Map.put("evidence_files", [
          "evidence/observation/#{String.replace(result["criterion"], " ", "-")}.md"
        ])
      end)
    end)
  end
end
