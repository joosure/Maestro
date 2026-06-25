defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyPlanTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyPlan
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "builds bounded operator apply plans from accepted enablement requests" do
    assert {:ok, plan} = OperatorApplyPlan.build(valid_request())

    assert plan["schema"] == "coding_pr_delivery.production_operator_apply_plan.v1"
    assert plan["status"] == "ready_for_operator_apply"
    assert plan["enablement_request_id"] == "enablement-tapd-cnb-shadow"
    assert plan["profile_instance_id"] == "coding-pr-delivery-production"
    assert plan["review_packet_id"] == "review-packet-tapd-cnb-shadow"
    assert plan["does_not_apply_settings"] == true
    assert plan["requires_operator_confirmation"] == true
    assert plan["can_apply_automatically"] == false
    assert plan["blockers"] == []

    assert Enum.any?(plan["operator_steps"], &(&1["id"] == "apply_gate_values"))
    assert Enum.any?(plan["operator_steps"], &(&1["id"] == "record_operator_apply" and &1["requires_operator_confirmation"] == true))
    assert Enum.any?(plan["rollback_steps"], &(&1["gate"] == Gates.transition_readiness_required_gate_key()))
  end

  test "projects invalid enablement requests into blocked apply plans" do
    request =
      valid_request()
      |> put_in(["review_decision", "status"], "blocked")
      |> put_in(["review_decision", "blockers"], [%{"code" => "missing_evidence"}])

    assert {:ok, plan} = OperatorApplyPlan.build(request)

    assert plan["status"] == "blocked"
    assert plan["enablement_request_id"] == "enablement-tapd-cnb-shadow"
    assert plan["operator_steps"] == []
    assert plan["rollback_steps"] == []
    assert plan["does_not_apply_settings"] == true
    assert plan["can_apply_automatically"] == false

    assert Enum.any?(plan["blockers"], &(&1["code"] == "review_decision_not_ready"))
  end

  test "projects non-object input into a blocked apply plan" do
    assert {:ok, plan} = OperatorApplyPlan.build(:invalid)

    assert plan["status"] == "blocked"
    assert plan["enablement_request_id"] == nil
    assert plan["operator_steps"] == []
    assert [%{"code" => "invalid_type"}] = plan["blockers"]
  end

  defp valid_request do
    %{
      "enablement_request_id" => "enablement-tapd-cnb-shadow",
      "requested_by" => "release-manager",
      "requested_at" => "2026-06-25T00:00:00Z",
      "review_decision" => ready_review_decision(),
      "scope" => %{
        "environment" => "production",
        "repositories" => ["acme/widgets"],
        "provider_matrix_entry_ids" => ["tapd-cnb-shadow"],
        "side_effect_mode" => "shadow_no_write"
      },
      "gate_values" => %{
        Gates.transition_readiness_required_gate_key() => false,
        Gates.enabled_gate_key() => true
      },
      "observation_window" => %{
        "duration_days" => 14,
        "success_criteria" => ["zero canonical writes", "zero shadow isolation violations"]
      },
      "rollback" => %{
        "owner" => "workflow-runtime",
        "disable_gates" => [
          Gates.transition_readiness_required_gate_key(),
          Gates.enabled_gate_key()
        ],
        "verified" => true
      },
      "acknowledged_non_claims" => [
        "multi_node_ownership",
        "automatic_durable_replay",
        "automatic_cold_start_provider_rebuild"
      ],
      "approvals" => [
        %{
          "role" => "workflow-runtime-owner",
          "owner" => "workflow-runtime",
          "decision" => "approved",
          "approved_at" => "2026-06-25T00:00:00Z"
        }
      ],
      "activation_control" => %{
        "change_ticket" => "CHANGE-123",
        "requires_operator_apply" => true,
        "applies_immediately" => false
      }
    }
  end

  defp ready_review_decision do
    %{
      "schema" => "coding_pr_delivery.production_review_decision.v1",
      "status" => "ready_for_approval",
      "review_packet_id" => "review-packet-tapd-cnb-shadow",
      "profile_instance_id" => "coding-pr-delivery-production",
      "provider_entries" => [
        %{
          "entry_id" => "tapd-cnb-shadow",
          "tracker" => %{"kind" => "tapd"},
          "repo_provider" => %{"kind" => "cnb"},
          "agent_provider" => %{"kind" => "codex"},
          "side_effect_mode" => "shadow_no_write",
          "topology_mode" => "singleton",
          "non_claims" => [
            "multi_node_ownership",
            "automatic_durable_replay",
            "automatic_cold_start_provider_rebuild"
          ]
        }
      ],
      "evidence_summary" => %{
        "scenario_evidence_count" => 9,
        "non_claim_acknowledgement_count" => 1
      },
      "owner_signoffs" => [
        %{
          "role" => "workflow-runtime-owner",
          "owner" => "workflow-runtime",
          "decision" => "approved"
        }
      ],
      "blockers" => [],
      "does_not_enable_production" => true,
      "raw_evidence_payload_included" => false
    }
  end
end
