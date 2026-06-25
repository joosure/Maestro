defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.GovernanceTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  test "accepts explicit retention tombstone cleanup and rollback evidence" do
    assert {:ok, packet} = Governance.validate_packet(valid_packet())

    assert packet["schema"] == Governance.schema()
    assert packet["profile_instance_id"] == "coding_pr_delivery.review_handoff.linear_github.staging"
    assert packet["durability_profile"]["retention_period_days"] == 30
    assert packet["data_governance"]["tombstone"]["metadata_fields"] == Governance.required_tombstone_fields()
    assert packet["rollback"]["preserves_stored_plans_and_evidence"] == true
    assert packet["rollback"]["deletes_records"] == false
  end

  test "rejects tombstone metadata that cannot explain prior readiness claims" do
    packet =
      valid_packet()
      |> put_in(["data_governance", "tombstone", "metadata_fields"], ["plan_id", "run_id"])

    assert {:error, %{code: "structured_execution_plan_production_governance_invalid", errors: errors}} =
             Governance.validate_packet(packet)

    assert Enum.any?(
             errors,
             &(&1.code == "missing_tombstone_metadata" and &1.path == ["data_governance", "tombstone", "metadata_fields", "issue_id"])
           )

    assert Enum.any?(
             errors,
             &(&1.code == "missing_tombstone_metadata" and &1.path == ["data_governance", "tombstone", "metadata_fields", "tombstone_reason"])
           )
  end

  test "rejects destructive rollback semantics" do
    packet =
      valid_packet()
      |> put_in(["rollback", "deletes_records"], true)
      |> put_in(["rollback", "rewrites_evidence"], true)
      |> put_in(["rollback", "makes_workpad_authoritative"], true)

    assert {:error, %{errors: errors}} = Governance.validate_packet(packet)

    assert Enum.any?(errors, &(&1.code == "invalid_destructive_rollback" and &1.path == ["rollback", "deletes_records"]))
    assert Enum.any?(errors, &(&1.code == "invalid_destructive_rollback" and &1.path == ["rollback", "rewrites_evidence"]))
    assert Enum.any?(errors, &(&1.code == "invalid_destructive_rollback" and &1.path == ["rollback", "makes_workpad_authoritative"]))
  end

  test "rejects non fail-closed scrubber behavior and legacy rollback gates" do
    packet =
      valid_packet()
      |> put_in(["data_governance", "scrubbing_pipeline", "failure_behavior"], "best_effort")
      |> update_in(["data_governance", "scrubbing_pipeline", "pattern_catalog_rules"], &List.delete(&1, "jwt"))
      |> put_in(["rollback", "disable_readiness_gate"], "review_handoff_required")

    assert {:error, %{errors: errors} = error} = Governance.validate_packet(packet)

    assert Enum.any?(
             errors,
             &(&1.code == "invalid_scrubbing_failure_behavior" and
                 &1.path == ["data_governance", "scrubbing_pipeline", "failure_behavior"])
           )

    assert Enum.any?(
             errors,
             &(&1.code == "missing_scrubbing_pattern_rule" and
                 &1.path == ["data_governance", "scrubbing_pipeline", "pattern_catalog_rules", "jwt"])
           )

    assert Enum.any?(errors, &(&1.code == "invalid_rollback_gate" and &1.path == ["rollback", "disable_readiness_gate"]))
    refute inspect(error) =~ "best_effort"
  end

  test "facade exposes production governance validation" do
    assert {:ok, %{"schema" => "workflow.execution_plan.production_governance.v1"}} =
             StructuredExecutionPlan.validate_production_governance(valid_packet())
  end

  defp valid_packet do
    %{
      "profile_instance_id" => "coding_pr_delivery.review_handoff.linear_github.staging",
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
        "disable_recording_gate" => Contract.enabled_gate_key(),
        "disable_rendering_gate" => Contract.render_workpad_gate_key(),
        "disable_readiness_gate" => Contract.transition_readiness_required_gate_key(),
        "disable_provider_adapters_gate" => Contract.provider_adapters_enabled_gate_key(),
        "preserves_stored_plans_and_evidence" => true,
        "deletes_records" => false,
        "rewrites_evidence" => false,
        "makes_workpad_authoritative" => false
      },
      "evidence_files" => [
        "evidence/structured-plan/governance/linear-github-staging.md"
      ]
    }
  end
end
