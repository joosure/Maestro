defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacketTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRunbook
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacket
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  test "accepts complete Phase 4 production review packets" do
    assert {:ok, packet} = ReviewPacket.validate(complete_review_packet())

    assert packet["schema"] == "coding_pr_delivery.production_review_packet.v1"
    assert packet["review_packet_id"] == "review-packet-tapd-cnb-shadow"
    assert packet["profile_instance_id"] == "coding-pr-delivery-production"
    assert packet["evidence_packet"]["schema"] == "coding_pr_delivery.production_evidence_packet.v1"
  end

  test "accepts complete Phase 4 production review packets for Linear + CNB shadow evidence" do
    assert {:ok, packet} =
             ReviewPacket.validate(complete_review_packet("linear-cnb-shadow", "linear", "shadow-run-linear-cnb-42"))

    assert packet["schema"] == "coding_pr_delivery.production_review_packet.v1"
    assert packet["review_packet_id"] == "review-packet-linear-cnb-shadow"
    assert packet["profile_instance_id"] == "coding-pr-delivery-production"
    assert packet["operator_inspection"]["contains_raw_evidence_payload"] == false
    assert packet["operator_inspection"]["gate_values"][Gates.transition_readiness_required_gate_key()] == false
    assert packet["authority_boundaries"]["raw_provider_passthrough_authorized"] == false

    assert Enum.all?(packet["evidence_packet"]["scenario_evidence"], fn evidence ->
             evidence["provider_matrix_entry_id"] == "linear-cnb-shadow" and
               evidence["evidence_kind"] == "shadow_integration" and
               evidence["production_write_performed"] == false and
               evidence["canonical_surface_mutated"] == false and
               evidence["shadow"]["run_id"] == "shadow-run-linear-cnb-42"
           end)
  end

  test "rejects packets whose nested evidence packet is invalid" do
    packet = Map.put(complete_review_packet(), "evidence_packet", %{})

    assert {:error, %{code: "coding_pr_delivery_review_packet_invalid", errors: errors}} =
             ReviewPacket.validate(packet)

    assert Enum.any?(
             errors,
             &(&1.code == "invalid_type" and &1.path == ["evidence_packet", "production_claim"])
           )
  end

  test "requires rollback instructions to use the external transition gate mapping" do
    packet =
      complete_review_packet()
      |> put_in(["rollback_instructions", "external_transition_readiness_gate"], "review_handoff_required")
      |> put_in(["rollback_instructions", "legacy_review_handoff_required_mapping"], false)
      |> put_in(["rollback_instructions", "disable_gates"], ["review_handoff_required"])

    assert {:error, %{errors: errors}} = ReviewPacket.validate(packet)

    assert Enum.any?(errors, &(&1.code == "invalid_transition_readiness_gate"))
    assert Enum.any?(errors, &(&1.code == "missing_legacy_gate_mapping"))
    assert Enum.any?(errors, &(&1.code == "missing_rollback_gate"))
  end

  test "rejects non-canonical authority boundaries and legacy operator gates" do
    packet =
      complete_review_packet()
      |> put_in(["authority_boundaries", "workpad_markdown_authoritative"], true)
      |> put_in(["operator_inspection", "gate_values", "review_handoff_required"], true)
      |> put_in(["operator_inspection", "contains_raw_evidence_payload"], true)

    assert {:error, %{errors: errors}} = ReviewPacket.validate(packet)

    assert Enum.any?(errors, &(&1.code == "invalid_authority_boundary" and &1.flag == "workpad_markdown_authoritative"))
    assert Enum.any?(errors, &(&1.code == "legacy_gate_name"))
    assert Enum.any?(errors, &(&1.code == "raw_evidence_payload_present"))
  end

  test "requires passing tests and approved owner sign-offs" do
    packet =
      complete_review_packet()
      |> put_in(["deterministic_test_matrix", Access.at(0), "status"], "failed")
      |> put_in(["owner_signoffs", Access.at(0), "decision"], "pending")

    assert {:error, %{errors: errors}} = ReviewPacket.validate(packet)

    assert Enum.any?(errors, &(&1.code == "test_not_passed" and &1.path == ["deterministic_test_matrix", 0, "status"]))
    assert Enum.any?(errors, &(&1.code == "signoff_not_approved"))
  end

  test "requires scrubbing pattern catalog rules in review packets" do
    packet =
      complete_review_packet()
      |> update_in(["scrubbing_pipeline", "pattern_catalog_rules"], &List.delete(&1, "private_keys"))

    assert {:error, %{errors: errors}} = ReviewPacket.validate(packet)

    assert Enum.any?(
             errors,
             &(&1.code == "missing_scrubbing_pattern_rule" and
                 &1.path == ["scrubbing_pipeline", "pattern_catalog_rules", "private_keys"])
           )
  end

  defp complete_review_packet(
         entry_id \\ "tapd-cnb-shadow",
         tracker_kind \\ "tapd",
         shadow_run_id \\ "shadow-run-1"
       ) do
    %{
      "review_packet_id" => "review-packet-#{entry_id}",
      "changed_source_specs" => [
        "specs/workflow/profiles/coding_pr_delivery/profile_spec.md",
        "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md"
      ],
      "implementation_refs" => [
        "commit:6505ae0",
        "local-patch:coding-pr-delivery-production-profile"
      ],
      "deterministic_test_matrix" => [
        %{
          "command" => "mise exec -- mix test",
          "status" => "passed"
        }
      ],
      "evidence_packet" => complete_evidence_packet(entry_id, tracker_kind, shadow_run_id),
      "rollback_instructions" => %{
        "owner" => "workflow-runtime",
        "external_transition_readiness_gate" => Gates.transition_readiness_required_gate_key(),
        "legacy_review_handoff_required_mapping" => true,
        "disable_gates" => [
          Gates.transition_readiness_required_gate_key(),
          Gates.enabled_gate_key(),
          Gates.render_workpad_gate_key(),
          Gates.provider_adapters_enabled_gate_key()
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
        "test_results" => [
          %{"name" => "scrubber evidence boundaries", "status" => "passed"}
        ]
      },
      "operator_inspection" => %{
        "schema" => "workflow.execution_plan.operator_inspection.v1",
        "gate_values" => %{
          Gates.transition_readiness_required_gate_key() => false,
          Gates.enabled_gate_key() => true
        },
        "candidate_gate_values_by_entry" => [
          %{
            "provider_matrix_entry_id" => entry_id,
            "gate_values" => %{
              Gates.transition_readiness_required_gate_key() => false,
              Gates.enabled_gate_key() => true
            }
          }
        ],
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
