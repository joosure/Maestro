defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.OperatorInspectionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.OperatorInspection
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract, as: WorkpadContract

  @created_at "2026-05-20T00:00:00Z"

  test "builds a bounded operator packet without raw evidence payloads" do
    plan =
      plan([
        item("repo.commit",
          required: true,
          criticality: Contract.handoff_blocking_criticality(),
          evidence_refs: [
            evidence_ref("ev-commit", "repo_commit", %{"head_sha" => "new456"}, "2026-05-20T00:00:03Z")
          ]
        ),
        item("validation.passed",
          required: true,
          criticality: Contract.handoff_blocking_criticality(),
          evidence_requirements: [requirement("repo_diff")],
          evidence_refs: [
            evidence_ref(
              "ev-validation",
              "repo_diff",
              %{"summary" => "Authorization: Bearer bearer-secret token=ghp_secret123"},
              "2026-05-20T00:00:01Z"
            )
          ]
        )
      ])
      |> Map.put("rendering", render_marker())

    gates = %{
      Contract.enabled_gate_key() => true,
      Contract.render_workpad_gate_key() => true,
      Contract.transition_readiness_required_gate_key() => true,
      Contract.provider_adapters_enabled_gate_key() => false
    }

    assert {:ok, packet} =
             OperatorInspection.build(plan,
               gates: gates,
               readiness_gate_result: %{"status" => "blocked", "reason" => "token=ghp_secret123"},
               rejected_updates: [%{"reason" => "Authorization: Bearer bearer-secret"}]
             )

    assert packet["schema"] == "workflow.execution_plan.operator_inspection.v1"
    assert packet["plan"]["plan_id"] == "plan-inspect-1"
    assert packet["gate_validation"]["valid"] == true
    assert packet["gate_values"][Contract.transition_readiness_required_gate_key()] == true
    assert packet["rollback_gate_values"]["disable_readiness_gate"]["gate"] == Contract.transition_readiness_required_gate_key()
    assert packet["rollback_gate_values"]["disable_readiness_gate"]["rollback_value"] == false
    assert packet["freshness_state"] == %{"status" => "stale", "stale_item_ids" => ["validation.passed"]}
    assert packet["latest_render_marker"][WorkpadContract.fingerprint_key()] == "fingerprint-123"

    assert [
             %{
               "item_id" => "repo.commit",
               "freshness" => "fresh"
             },
             %{
               "item_id" => "validation.passed",
               "evidence_ref_count" => 1,
               "freshness" => "stale"
             }
           ] = packet["required_item_statuses"]

    assert Enum.any?(packet["evidence_refs"], &(&1["evidence_id"] == "ev-validation" and &1["payload_present"] == true))
    refute inspect(packet) =~ "bearer-secret"
    refute inspect(packet) =~ "ghp_secret123"
    refute inspect(packet) =~ "summary"
  end

  test "validates gate packets and rejects legacy readiness gate names" do
    gates =
      Contract.gate_defaults()
      |> Map.put("review_handoff_required", true)
      |> Map.put(Contract.render_workpad_gate_key(), "yes")

    assert %{"valid" => false, "errors" => errors} = OperatorInspection.validate_gates(gates)

    assert Enum.any?(errors, &(&1["code"] == "unknown_gate_key" and &1["path"] == ["gates", "review_handoff_required"]))
    assert Enum.any?(errors, &(&1["code"] == "invalid_gate_value" and &1["path"] == ["gates", Contract.render_workpad_gate_key()]))
  end

  test "facade exposes operator inspection projection" do
    assert {:ok, %{"schema" => "workflow.execution_plan.operator_inspection.v1"}} =
             StructuredExecutionPlan.operator_inspection(plan([item("agent.plan")]))
  end

  defp plan(items) do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => "plan-inspect-1",
      "run_id" => "run-inspect-1",
      "issue_id" => "TES-90",
      "tracker_kind" => "linear",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "route_key" => "developing",
      "status" => "active",
      "items" => items,
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp item(item_id, opts \\ []) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => "tool_evidence",
      "status" => Keyword.get(opts, :status, "pending"),
      "required" => Keyword.get(opts, :required, false),
      "criticality" => Keyword.get(opts, :criticality, Contract.informational_criticality()),
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => Keyword.get(opts, :evidence_requirements, []),
      "evidence_refs" => Keyword.get(opts, :evidence_refs, []),
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp requirement(kind) do
    %{
      "evidence_kind" => kind,
      "required_fields" => [],
      "trust_classes" => ["tool_generated"]
    }
  end

  defp evidence_ref(id, kind, payload, observed_at) do
    %{
      "evidence_id" => id,
      "evidence_kind" => kind,
      "source" => "tool_generated",
      "producer" => "test",
      "run_id" => "run-inspect-1",
      "issue_id" => "TES-90",
      "observed_at" => observed_at,
      "payload" => payload
    }
  end

  defp render_marker do
    %{
      "schema" => WorkpadContract.render_schema(),
      "plan_id" => "plan-inspect-1",
      "plan_revision" => 1,
      "tracker_kind" => "linear",
      "mode" => "preview",
      "rendered_item_count" => 2,
      "fingerprint" => "fingerprint-123",
      "workpad_id" => "workpad-1"
    }
  end
end
