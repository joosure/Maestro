defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewDecisionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRunbook
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewDecision
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  test "projects accepted review packets into bounded ready decisions" do
    assert {:ok, decision} = ReviewDecision.build(complete_review_packet())

    assert decision["schema"] == "coding_pr_delivery.production_review_decision.v1"
    assert decision["status"] == "ready_for_approval"
    assert decision["review_packet_id"] == "review-packet-tapd-cnb-shadow"
    assert decision["profile_instance_id"] == "coding-pr-delivery-production"
    assert decision["does_not_enable_production"] == true
    assert decision["raw_evidence_payload_included"] == false
    assert decision["blockers"] == []

    assert [
             %{
               "entry_id" => "tapd-cnb-shadow",
               "tracker" => %{"kind" => "tapd"},
               "repo_provider" => %{"kind" => "cnb"},
               "side_effect_mode" => "shadow_no_write",
               "non_claims" => non_claims
             }
           ] = decision["provider_entries"]

    assert "multi_node_ownership" in non_claims
    assert decision["evidence_summary"]["scenario_evidence_count"] > 0
    assert decision["evidence_summary"]["non_claim_acknowledgement_count"] == 1
  end

  test "projects Linear + CNB shadow review packets into bounded ready decisions" do
    assert {:ok, decision} =
             ReviewDecision.build(complete_review_packet("linear-cnb-shadow", "linear", "shadow-run-linear-cnb-42"))

    assert decision["schema"] == "coding_pr_delivery.production_review_decision.v1"
    assert decision["status"] == "ready_for_approval"
    assert decision["review_packet_id"] == "review-packet-linear-cnb-shadow"
    assert decision["profile_instance_id"] == "coding-pr-delivery-production"
    assert decision["does_not_enable_production"] == true
    assert decision["raw_evidence_payload_included"] == false
    assert decision["blockers"] == []

    assert [
             %{
               "entry_id" => "linear-cnb-shadow",
               "tracker" => %{"kind" => "linear"},
               "repo_provider" => %{"kind" => "cnb"},
               "side_effect_mode" => "shadow_no_write",
               "topology_mode" => "singleton",
               "non_claims" => non_claims
             }
           ] = decision["provider_entries"]

    assert "multi_node_ownership" in non_claims
    assert decision["evidence_summary"]["scenario_evidence_count"] > 0
    assert decision["evidence_summary"]["non_claim_acknowledgement_count"] == 1
  end

  test "projects invalid review packets into bounded blocked decisions" do
    packet =
      complete_review_packet()
      |> put_in(["owner_signoffs", Access.at(0), "decision"], "pending")

    assert {:ok, decision} = ReviewDecision.build(packet)

    assert decision["status"] == "blocked"
    assert decision["review_packet_id"] == "review-packet-tapd-cnb-shadow"
    assert decision["profile_instance_id"] == "coding-pr-delivery-production"
    assert decision["does_not_enable_production"] == true
    assert decision["raw_evidence_payload_included"] == false

    assert Enum.any?(
             decision["blockers"],
             &(&1["code"] == "signoff_not_approved" and &1["path"] == ["owner_signoffs", 0, "decision"])
           )
  end

  test "projects non-object input into a blocked decision" do
    assert {:ok, decision} = ReviewDecision.build(:invalid)

    assert decision["status"] == "blocked"
    assert decision["review_packet_id"] == nil
    assert decision["provider_entries"] == []
    assert [%{"code" => "invalid_type"}] = decision["blockers"]
  end

  defp complete_review_packet(
         entry_id \\ "tapd-cnb-shadow",
         tracker_kind \\ "tapd",
         shadow_run_id \\ "shadow-run-1"
       ) do
    %{
      "review_packet_id" => "review-packet-#{entry_id}",
      "changed_source_specs" => [
        "specs/workflow/profiles/coding_pr_delivery/profile_spec.md"
      ],
      "implementation_refs" => ["commit:6505ae0"],
      "deterministic_test_matrix" => [%{"command" => "mise exec -- mix test", "status" => "passed"}],
      "evidence_packet" => complete_evidence_packet(entry_id, tracker_kind, shadow_run_id),
      "provider_preflight_reports" => [passed_preflight_report(entry_id, shadow_run_id)],
      "rollback_instructions" => %{
        "owner" => "workflow-runtime",
        "external_transition_readiness_gate" => Gates.transition_readiness_required_gate_key(),
        "legacy_review_handoff_required_mapping" => true,
        "disable_gates" => [
          Gates.transition_readiness_required_gate_key(),
          Gates.enabled_gate_key()
        ]
      },
      "scrubbing_pipeline" => %{
        "owner" => "workflow-runtime-security",
        "pattern_catalog_version" => "2026-06-25",
        "pattern_catalog_rules" => Governance.required_scrubbing_pattern_rules(),
        "failure_behavior" => "fail_closed",
        "enforced_boundaries" => [
          "structured_plan_evidence_write",
          "structured_plan_render",
          "review_packet_render"
        ],
        "test_results" => [%{"name" => "scrubber evidence boundaries", "status" => "passed"}]
      },
      "operator_inspection" => %{
        "schema" => "workflow.execution_plan.operator_inspection.v1",
        "gate_values" => %{Gates.transition_readiness_required_gate_key() => false},
        "contains_raw_evidence_payload" => false,
        "workpad_markdown_authoritative" => false
      },
      "retention_policy" => %{
        "retention_class" => "workflow_audit_staging",
        "retention_period_days" => 30,
        "cleanup_owner" => "workflow-runtime",
        "tombstone_preserving" => true
      },
      "authority_boundaries" => %{
        "prompt_wording_authoritative" => false,
        "workpad_markdown_authoritative" => false,
        "raw_provider_passthrough_authorized" => false,
        "schema_support_alone_sufficient" => false
      },
      "owner_signoffs" => [
        %{
          "role" => "workflow-runtime-owner",
          "owner" => "workflow-runtime",
          "decision" => "approved",
          "approved_at" => "2026-06-25T00:00:00Z"
        }
      ]
    }
  end

  defp complete_evidence_packet(entry_id, tracker_kind, shadow_run_id) do
    claim = production_claim(entry_id, tracker_kind, shadow_run_id)
    assert {:ok, runbook} = EvidenceRunbook.build(claim)

    %{
      "production_claim" => claim,
      "scenario_evidence" => scenario_evidence(runbook),
      "non_claim_acknowledgements" => non_claim_acknowledgements(runbook)
    }
  end

  defp passed_preflight_report(entry_id, shadow_run_id) do
    assert {:ok, phase2_plan} = build_phase2_plan(phase2_template(entry_id), shadow_run_id)

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

  defp build_phase2_plan(:tapd_cnb_shadow, shadow_run_id) do
    Phase2EvidencePlan.build(:tapd_cnb_shadow, tapd_cnb_shadow_run_id: shadow_run_id)
  end

  defp build_phase2_plan(:linear_cnb_shadow, shadow_run_id) do
    Phase2EvidencePlan.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: shadow_run_id)
  end

  defp phase2_template("tapd-cnb-shadow"), do: :tapd_cnb_shadow
  defp phase2_template("linear-cnb-shadow"), do: :linear_cnb_shadow

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
      "production_enabled" => false
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
          "collected_at" => "2026-06-25T00:00:00Z",
          "evidence_files" => ["evidence/live/#{entry["entry_id"]}/#{scenario["id"]}.md"],
          "production_write_performed" => false,
          "canonical_surface_mutated" => false,
          "shadow" => %{
            "prefix" => OneShotContract.shadow_prefix(),
            "run_id" => get_in(entry, ["shadow_requirements", "run_id"]) || "shadow-run-1",
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
        "acknowledged_at" => "2026-06-25T00:00:00Z"
      }
    end)
  end

  defp production_claim(entry_id, tracker_kind, shadow_run_id) do
    %{
      "profile_instance_id" => "coding-pr-delivery-production",
      "provider_matrix" => [shadow_entry(entry_id, tracker_kind, shadow_run_id)],
      "production_governance" => [governance_packet(entry_id)]
    }
  end

  defp shadow_entry(entry_id, tracker_kind, shadow_run_id) do
    %{
      "id" => entry_id,
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "tracker" => %{"kind" => tracker_kind},
      "repo_provider" => %{"kind" => "cnb"},
      "agent_provider" => %{"kind" => "codex"},
      "repository_class" => "single_repo_change_proposal",
      "candidate_discovery" => "runtime_targeted",
      "side_effect_mode" => OneShotContract.shadow_mode(),
      "structured_plan_gates" => %{
        Gates.enabled_gate_key() => true,
        Gates.provider_adapters_enabled_gate_key() => true,
        Gates.render_workpad_gate_key() => true,
        Gates.transition_readiness_required_gate_key() => false
      },
      "typed_tool_inventory" => %{
        "tracker" => ["tracker.issue_snapshot", "tracker.move_issue"],
        "repo_core" => ["repo.diff", "repo.head_sha"],
        "repo_provider" => ["repo_provider.change_proposal_snapshot", "repo_provider.change_proposal_checks"]
      },
      "deployment_topology" => %{
        "mode" => "singleton",
        "readiness_check" => "Reconciliation.runtime_topology_readiness/1"
      },
      "shadow" => %{
        "prefix" => OneShotContract.shadow_prefix(),
        "run_id" => shadow_run_id,
        "authority" => OneShotContract.shadow_authority(),
        "canonical_authority" => false,
        "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
      },
      "evidence_files" => ["evidence/provider-matrix/#{entry_id}.md"],
      "recovery" => %{"model" => "operator_one_shot"},
      "rollback" => %{
        "owner" => "workflow-runtime",
        "disable_readiness_gate" => Gates.transition_readiness_required_gate_key()
      }
    }
  end

  defp governance_packet(provider_matrix_entry_id) do
    %{
      "provider_matrix_entry_id" => provider_matrix_entry_id,
      "profile_instance_id" => "coding-pr-delivery-production",
      "durability_profile" => %{
        "storage_backend" => "sqlite",
        "restart_behavior" => "survives process and worker restarts",
        "backup_restore" => "daily backup with documented restore drill",
        "retention_class" => "workflow_audit_staging",
        "retention_period_days" => 30,
        "cleanup_behavior" => "tombstone_preserving_prune",
        "survives_process_restart" => true,
        "survives_worker_restart" => true,
        "survives_service_restart" => true
      },
      "data_governance" => %{
        "data_classification" => "workflow_audit",
        "redaction_policy" => "bounded_payload_summaries_only",
        "retention_class" => "workflow_audit_staging",
        "retention_period_days" => 30,
        "cleanup_owner" => "workflow-runtime",
        "cleanup_schedule" => "daily",
        "scrubbing_pipeline" => %{
          "owner" => "workflow-runtime-security",
          "pattern_catalog_version" => "2026-06-25",
          "pattern_catalog_rules" => Governance.required_scrubbing_pattern_rules(),
          "failure_behavior" => "fail_closed",
          "enforced_boundaries" => [
            "structured_plan_evidence_write",
            "structured_plan_render",
            "review_packet_render"
          ]
        },
        "tombstone" => %{
          "metadata_fields" => Governance.required_tombstone_fields(),
          "prevents_id_reuse" => true,
          "prevents_hidden_readiness_claims" => true,
          "preserves_audit_trail" => true
        }
      },
      "rollback" => %{
        "disable_recording_gate" => Gates.enabled_gate_key(),
        "disable_rendering_gate" => Gates.render_workpad_gate_key(),
        "disable_readiness_gate" => Gates.transition_readiness_required_gate_key(),
        "disable_provider_adapters_gate" => Gates.provider_adapters_enabled_gate_key(),
        "preserves_stored_plans_and_evidence" => true,
        "deletes_records" => false,
        "rewrites_evidence" => false,
        "makes_workpad_authoritative" => false
      },
      "evidence_files" => ["evidence/structured-plan/governance/#{provider_matrix_entry_id}.md"]
    }
  end
end
