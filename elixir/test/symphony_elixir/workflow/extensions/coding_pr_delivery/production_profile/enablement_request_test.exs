defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequestTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequest
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "accepts scoped enablement requests over ready review decisions" do
    assert {:ok, request} = EnablementRequest.validate(valid_request())

    assert request["schema"] == "coding_pr_delivery.production_enablement_request.v1"
    assert request["enablement_request_id"] == "enablement-tapd-cnb-shadow"
    assert request["profile_instance_id"] == "coding-pr-delivery-production"
    assert request["review_packet_id"] == "review-packet-tapd-cnb-shadow"
    assert request["does_not_enable_production"] == true
    assert request["scope"]["side_effect_mode"] == "shadow_no_write"
  end

  test "rejects blocked review decisions" do
    request =
      valid_request()
      |> put_in(["review_decision", "status"], "blocked")
      |> put_in(["review_decision", "blockers"], [%{"code" => "missing_evidence"}])

    assert {:error, %{code: "coding_pr_delivery_enablement_request_invalid", errors: errors}} =
             EnablementRequest.validate(request)

    assert Enum.any?(errors, &(&1.code == "review_decision_not_ready"))
    assert Enum.any?(errors, &(&1.code == "review_decision_blocked"))
  end

  test "rejects scope that is outside the reviewed provider entry or side-effect mode" do
    request =
      valid_request()
      |> put_in(["scope", "provider_matrix_entry_ids"], ["unknown-entry", "tapd-cnb-shadow"])
      |> put_in(["scope", "side_effect_mode"], "ready_to_land_write")

    assert {:error, %{errors: errors}} = EnablementRequest.validate(request)

    assert Enum.any?(errors, &(&1.code == "unknown_provider_matrix_entry" and &1.provider_matrix_entry_id == "unknown-entry"))
    assert Enum.any?(errors, &(&1.code == "side_effect_mode_escalation" and &1.provider_matrix_entry_id == "tapd-cnb-shadow"))
  end

  test "rejects legacy gates and ready-to-land requests without transition readiness" do
    request =
      valid_request()
      |> put_in(["review_decision", "provider_entries", Access.at(0), "side_effect_mode"], "ready_to_land_write")
      |> put_in(["scope", "side_effect_mode"], "ready_to_land_write")
      |> put_in(["gate_values", Gates.transition_readiness_required_gate_key()], false)
      |> put_in(["gate_values", "review_handoff_required"], true)

    assert {:error, %{errors: errors}} = EnablementRequest.validate(request)

    assert Enum.any?(errors, &(&1.code == "legacy_gate_name"))
    assert Enum.any?(errors, &(&1.code == "ready_to_land_without_transition_gate"))
  end

  test "requires acknowledged non-claims, verified rollback, approvals, and operator apply" do
    request =
      valid_request()
      |> Map.put("acknowledged_non_claims", ["automatic_durable_replay"])
      |> put_in(["rollback", "verified"], false)
      |> put_in(["approvals", Access.at(0), "decision"], "pending")
      |> put_in(["activation_control", "applies_immediately"], true)

    assert {:error, %{errors: errors}} = EnablementRequest.validate(request)

    assert Enum.any?(errors, &(&1.code == "missing_non_claim_acknowledgement" and &1.non_claim == "multi_node_ownership"))
    assert Enum.any?(errors, &(&1.code == "rollback_not_verified"))
    assert Enum.any?(errors, &(&1.code == "approval_not_approved"))
    assert Enum.any?(errors, &(&1.code == "immediate_activation"))
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
