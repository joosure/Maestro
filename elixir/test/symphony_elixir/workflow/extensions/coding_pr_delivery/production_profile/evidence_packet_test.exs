defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacketTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacket
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRunbook
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  test "accepts complete Phase 2 evidence packets for a shadow provider claim" do
    assert {:ok, packet} = EvidencePacket.validate(complete_packet())

    assert packet["schema"] == "coding_pr_delivery.production_evidence_packet.v1"
    assert packet["profile_instance_id"] == "coding-pr-delivery-production"
    assert packet["runbook"]["claim_authority"] == "diagnostic_runbook_only"

    expected_count =
      packet["runbook"]["entries"]
      |> Enum.flat_map(& &1["scenario_checklist"])
      |> length()

    assert length(packet["scenario_evidence"]) == expected_count

    assert [
             %{
               "provider_matrix_entry_id" => "tapd-cnb-shadow",
               "non_claims" => non_claims
             }
           ] = packet["non_claim_acknowledgements"]

    assert "multi_node_ownership" in non_claims
  end

  test "accepts complete Phase 2 evidence packets for a Linear + CNB shadow claim" do
    assert {:ok, packet} =
             EvidencePacket.validate(complete_packet("linear-cnb-shadow", "linear", "shadow-run-linear-cnb-42"))

    assert packet["schema"] == "coding_pr_delivery.production_evidence_packet.v1"
    assert packet["profile_instance_id"] == "coding-pr-delivery-production"

    assert [
             %{
               "provider_matrix_entry_id" => "linear-cnb-shadow",
               "non_claims" => non_claims
             }
           ] = packet["non_claim_acknowledgements"]

    assert "multi_node_ownership" in non_claims

    assert Enum.all?(packet["scenario_evidence"], fn evidence ->
             evidence["provider_matrix_entry_id"] == "linear-cnb-shadow" and
               evidence["evidence_kind"] == "shadow_integration" and
               evidence["production_write_performed"] == false and
               evidence["canonical_surface_mutated"] == false and
               evidence["shadow"]["run_id"] == "shadow-run-linear-cnb-42"
           end)
  end

  test "requires evidence for every runbook scenario" do
    packet = complete_packet()
    [removed | remaining] = packet["scenario_evidence"]
    packet = Map.put(packet, "scenario_evidence", remaining)

    assert {:error, %{code: "coding_pr_delivery_evidence_packet_invalid", errors: errors}} =
             EvidencePacket.validate(packet)

    assert Enum.any?(
             errors,
             &(&1.code == "missing_scenario_evidence" and
                 &1.provider_matrix_entry_id == removed["provider_matrix_entry_id"] and
                 &1.scenario_id == removed["scenario_id"])
           )
  end

  test "rejects shadow evidence that claims production authority or writes" do
    packet =
      complete_packet()
      |> update_in(["scenario_evidence", Access.at(0)], fn record ->
        record
        |> put_in(["shadow", "prefix"], "[NOT_SHADOW]")
        |> put_in(["shadow", "canonical_authority"], true)
        |> Map.put("production_write_performed", true)
        |> Map.put("canonical_surface_mutated", true)
      end)

    assert {:error, %{errors: errors}} = EvidencePacket.validate(packet)

    assert Enum.any?(errors, &(&1.code == "invalid_shadow_prefix"))
    assert Enum.any?(errors, &(&1.code == "shadow_canonical_authority"))
    assert Enum.any?(errors, &(&1.code == "shadow_production_write"))
    assert Enum.any?(errors, &(&1.code == "shadow_canonical_surface_mutated"))
  end

  test "rejects invalid production claims before accepting evidence" do
    packet =
      complete_packet()
      |> put_in(["production_claim", "profile_instance_id"], "")

    assert {:error, %{errors: errors}} = EvidencePacket.validate(packet)

    assert Enum.any?(
             errors,
             &(&1.code == "required_field_missing" and &1.path == ["production_claim", "profile_instance_id"])
           )
  end

  test "requires explicit non-claim acknowledgements for each provider entry" do
    packet = Map.put(complete_packet(), "non_claim_acknowledgements", [])

    assert {:error, %{errors: errors}} = EvidencePacket.validate(packet)

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["non_claim_acknowledgements"]))
  end

  defp complete_packet(
         entry_id \\ "tapd-cnb-shadow",
         tracker_kind \\ "tapd",
         shadow_run_id \\ "shadow-run-1"
       ) do
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
