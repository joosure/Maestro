defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfileTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  test "exposes stable pure admission entrypoints" do
    assert "shadow_no_write" in ProductionProfile.side_effect_modes()
    assert {:ok, %{"id" => "tapd-cnb-shadow"}} = ProductionProfile.validate_provider_matrix_entry(shadow_entry())

    assert {:ok, %{"provider_matrix" => [%{"id" => "tapd-cnb-shadow"}]}} =
             ProductionProfile.validate_provider_matrix(provider_matrix_claim())

    assert {:error, %{code: "coding_pr_delivery_typed_tool_exception_invalid", errors: errors}} =
             ProductionProfile.validate_typed_tool_exception(%{})

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["exception_id"]))

    assert {:error, %{code: "coding_pr_delivery_evidence_packet_invalid"}} =
             ProductionProfile.validate_evidence_packet(%{})

    assert {:error, %{code: "coding_pr_delivery_review_packet_invalid"}} =
             ProductionProfile.validate_review_packet(%{})
  end

  test "builds diagnostic runbooks through the facade after claim admission" do
    assert {:ok, %{"profile_instance_id" => "coding-pr-delivery-production"}} =
             ProductionProfile.validate_claim(production_claim())

    assert {:ok, runbook} = ProductionProfile.build_evidence_runbook(production_claim())

    assert runbook["schema"] == "coding_pr_delivery.production_evidence_runbook.v1"
    assert runbook["claim_authority"] == "diagnostic_runbook_only"
    assert runbook["does_not_execute_providers"] == true

    assert [
             %{
               "entry_id" => "tapd-cnb-shadow",
               "tracker" => %{"kind" => "tapd"},
               "repo_provider" => %{"kind" => "cnb"},
               "shadow_requirements" => shadow_requirements
             }
           ] = runbook["entries"]

    assert shadow_requirements["prefix"] == OneShotContract.shadow_prefix()
    assert shadow_requirements["canonical_authority"] == false
  end

  test "does not build runbooks for invalid production claims" do
    assert {:error, %{code: "coding_pr_delivery_production_claim_invalid", errors: errors}} =
             ProductionProfile.build_evidence_runbook(%{})

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["profile_instance_id"]))
  end

  defp production_claim do
    %{
      "profile_instance_id" => "coding-pr-delivery-production",
      "provider_matrix" => [shadow_entry()],
      "production_governance" => [governance_packet("tapd-cnb-shadow")]
    }
  end

  defp provider_matrix_claim do
    %{
      "profile_instance_id" => "coding-pr-delivery-production",
      "provider_matrix" => [shadow_entry()]
    }
  end

  defp shadow_entry do
    %{
      "id" => "tapd-cnb-shadow",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "tracker" => %{"kind" => "tapd"},
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
        "run_id" => "shadow-run-1",
        "authority" => OneShotContract.shadow_authority(),
        "canonical_authority" => false,
        "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
      },
      "evidence_files" => ["evidence/provider-matrix/tapd-cnb-shadow.md"],
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
