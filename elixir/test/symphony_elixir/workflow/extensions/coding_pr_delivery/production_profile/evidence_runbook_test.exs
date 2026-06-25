defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRunbookTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRunbook
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  test "builds provider-specific Phase 2 evidence runbooks from accepted claims" do
    assert {:ok, runbook} = EvidenceRunbook.build(production_claim())

    assert runbook["schema"] == "coding_pr_delivery.production_evidence_runbook.v1"
    assert runbook["does_not_execute_providers"] == true
    assert runbook["claim_authority"] == "diagnostic_runbook_only"

    assert [ready, shadow] = runbook["entries"]

    assert ready["entry_id"] == "linear-github-ready"
    assert ready["ready_to_land_requirements"]["transition_readiness_required"] == true
    assert ready["shadow_requirements"] == nil
    assert "automatic_cold_start_provider_rebuild_unless_evidenced" in ready["non_claims"]
    assert Enum.any?(ready["scenario_checklist"], &(&1["id"] == "reconciliation_ready_to_land_write"))
    assert Enum.any?(ready["collection_steps"], &(&1["id"] == "verify_transition_readiness_gate"))

    assert shadow["entry_id"] == "tapd-cnb-shadow"
    assert shadow["shadow_requirements"]["prefix"] == OneShotContract.shadow_prefix()
    assert shadow["shadow_requirements"]["run_id"] == "shadow-run-1"
    assert shadow["shadow_requirements"]["canonical_authority"] == false
    assert "multi_node_ownership" in shadow["non_claims"]
    assert Enum.any?(shadow["scenario_checklist"], &(&1["id"] == "shadow_decision_chain"))
    assert Enum.any?(shadow["collection_steps"], &(&1["id"] == "verify_shadow_isolation"))
  end

  test "builds Linear + CNB shadow evidence runbooks with diagnostic-only requirements" do
    assert {:ok, %{"entries" => [entry]}} =
             EvidenceRunbook.build(production_claim([shadow_entry("linear-cnb-shadow", "linear", "cnb")], []))

    assert entry["entry_id"] == "linear-cnb-shadow"
    assert entry["tracker"]["kind"] == "linear"
    assert entry["repo_provider"]["kind"] == "cnb"
    assert entry["side_effect_mode"] == OneShotContract.shadow_mode()
    assert entry["ready_to_land_requirements"] == nil
    assert entry["shadow_requirements"]["prefix"] == OneShotContract.shadow_prefix()
    assert entry["shadow_requirements"]["run_id"] == "shadow-run-1"
    assert entry["shadow_requirements"]["authority"] == OneShotContract.shadow_authority()
    assert entry["shadow_requirements"]["canonical_authority"] == false
    assert "multi_node_ownership" in entry["non_claims"]
    assert Enum.any?(entry["scenario_checklist"], &(&1["id"] == "shadow_isolation"))
    assert Enum.any?(entry["collection_steps"], &(&1["id"] == "verify_shadow_isolation"))
    assert entry["evidence_files"]["provider_matrix"] == ["evidence/provider-matrix/linear-cnb-shadow.md"]
    assert entry["evidence_files"]["typed_tool_exceptions"] == []
  end

  test "carries evidence destinations and matching exception evidence" do
    assert {:ok, %{"entries" => [ready, shadow]}} = EvidenceRunbook.build(production_claim())

    assert ready["evidence_files"]["provider_matrix"] == ["evidence/provider-matrix/linear-github-ready.md"]
    assert ready["evidence_files"]["production_governance"] == ["evidence/structured-plan/governance/linear-github-ready.md"]
    assert ready["evidence_files"]["typed_tool_exceptions"] == ["evidence/typed-tool-exceptions/linear-github-review-read.md"]

    assert shadow["evidence_files"]["provider_matrix"] == ["evidence/provider-matrix/tapd-cnb-shadow.md"]
    assert shadow["evidence_files"]["production_governance"] == ["evidence/structured-plan/governance/tapd-cnb-shadow.md"]
    assert shadow["evidence_files"]["typed_tool_exceptions"] == []
  end

  test "rejects invalid claims before generating a runbook" do
    claim =
      production_claim()
      |> put_in(["provider_matrix", Access.at(0), "structured_plan_gates", Gates.transition_readiness_required_gate_key()], false)

    assert {:error, %{code: "coding_pr_delivery_production_claim_invalid", errors: errors}} = EvidenceRunbook.build(claim)

    assert Enum.any?(
             errors,
             &(&1.code == "transition_readiness_required" and
                 &1.path == ["provider_matrix", 0, "structured_plan_gates", Gates.transition_readiness_required_gate_key()])
           )
  end

  test "rejects non-object input through production claim admission" do
    assert {:error, %{code: "coding_pr_delivery_production_claim_invalid", errors: [%{code: "invalid_type"}]}} =
             EvidenceRunbook.build(:invalid)
  end

  defp production_claim do
    entries = [ready_to_land_entry(), shadow_entry("tapd-cnb-shadow", "tapd", "cnb")]

    production_claim(entries, [typed_tool_exception()])
  end

  defp production_claim(entries, typed_tool_exceptions) do
    %{
      "profile_instance_id" => "coding_pr_delivery.production.claim",
      "provider_matrix" => entries,
      "production_governance" => Enum.map(entries, &governance_packet(&1["id"])),
      "typed_tool_exceptions" => typed_tool_exceptions
    }
  end

  defp ready_to_land_entry do
    base_entry("linear-github-ready", "linear", "github")
    |> Map.merge(%{
      "side_effect_mode" => "ready_to_land_write",
      "structured_plan_gates" => gates(true),
      "deployment_topology" => %{
        "mode" => "distributed_lock",
        "ownership_proof" => "redis-lock:workflow:coding-pr-delivery"
      }
    })
  end

  defp shadow_entry(id, tracker, repo_provider) do
    base_entry(id, tracker, repo_provider)
    |> Map.merge(%{
      "side_effect_mode" => OneShotContract.shadow_mode(),
      "structured_plan_gates" => gates(false),
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
      }
    })
  end

  defp base_entry(id, tracker, repo_provider) do
    %{
      "id" => id,
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "tracker" => %{"kind" => tracker},
      "repo_provider" => %{"kind" => repo_provider},
      "agent_provider" => %{"kind" => "codex"},
      "repository_class" => "single_repo_change_proposal",
      "candidate_discovery" => "runtime_targeted",
      "typed_tool_inventory" => %{
        "tracker" => ["tracker.issue_snapshot", "tracker.move_issue"],
        "repo_core" => ["repo.diff", "repo.head_sha"],
        "repo_provider" => ["repo_provider.change_proposal_snapshot", "repo_provider.change_proposal_checks"]
      },
      "evidence_files" => ["evidence/provider-matrix/#{id}.md"],
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
      "profile_instance_id" => "coding_pr_delivery.production.claim",
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

  defp typed_tool_exception do
    %{
      "exception_id" => "typed-tool-exception-linear-github-1",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "tracker" => %{"kind" => "linear"},
      "repo_provider" => %{"kind" => "github"},
      "agent_provider" => %{"kind" => "codex"},
      "repository_class" => "single_repo_change_proposal",
      "workspace_class" => "staging_workspace",
      "route_set" => ["developing", "review"],
      "operation_set" => ["repo_provider.review.read"],
      "fallback_authority" => %{
        "owner" => "workflow-runtime",
        "authority_kind" => "temporary_backend_adapter",
        "accepted_by_profile_owners" => true
      },
      "compensating_controls" => ["read_only_operation", "bounded_schema_allowlist"],
      "input_schema_allowlist" => %{
        "schema_ids" => ["repo_provider.review.read.v1"],
        "rejects_unknown_fields" => true
      },
      "limits" => %{"max_calls_per_run" => 3, "max_concurrency" => 1},
      "audit_logging" => %{
        "event_name" => "coding_pr_delivery_typed_tool_exception_used",
        "retention_class" => "workflow_audit_staging"
      },
      "deterministic_tests" => [
        "test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile/typed_tool_exception_test.exs"
      ],
      "real_integration_evidence" => ["evidence/typed-tool-exceptions/linear-github-review-read.md"],
      "operator_observability" => %{
        "metrics" => ["typed_tool_exception_used_total"],
        "alerts" => ["typed_tool_exception_usage_outside_scope"],
        "runbook" => "runbooks/coding-pr-delivery/typed-tool-exception.md"
      },
      "rollback" => %{
        "owner" => "workflow-runtime",
        "instructions" => "Remove exception id from production enablement packet and require typed tool inventory.",
        "disables_exception" => true,
        "restores_typed_tool_requirement" => true
      },
      "expires_at" => "2026-07-25T00:00:00Z"
    }
  end

  defp gates(transition_readiness_required) do
    %{
      Gates.enabled_gate_key() => true,
      Gates.provider_adapters_enabled_gate_key() => true,
      Gates.render_workpad_gate_key() => true,
      Gates.transition_readiness_required_gate_key() => transition_readiness_required
    }
  end
end
