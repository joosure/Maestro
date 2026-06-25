defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecordTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecord
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "accepts records that match an externally applied operator plan" do
    assert {:ok, record} = OperatorApplyRecord.validate(valid_record())

    assert record["schema"] == "coding_pr_delivery.production_operator_apply_record.v1"
    assert record["apply_record_id"] == "apply-record-tapd-cnb-shadow"
    assert record["enablement_request_id"] == "enablement-tapd-cnb-shadow"
    assert record["profile_instance_id"] == "coding-pr-delivery-production"
    assert record["records_external_operator_apply"] == true
    assert record["does_not_apply_settings"] == true
    assert "apply_gate_values" in record["completed_operator_step_ids"]
  end

  test "rejects blocked or automatic apply plans" do
    record =
      valid_record()
      |> put_in(["operator_apply_plan", "status"], "blocked")
      |> put_in(["operator_apply_plan", "can_apply_automatically"], true)

    assert {:error, %{code: "coding_pr_delivery_operator_apply_record_invalid", errors: errors}} =
             OperatorApplyRecord.validate(record)

    assert Enum.any?(errors, &(&1.code == "operator_apply_plan_not_ready"))
    assert Enum.any?(errors, &(&1.code == "automatic_apply_allowed"))
  end

  test "rejects automatic apply metadata and gate drift" do
    record =
      valid_record()
      |> put_in(["apply_metadata", "automatic_apply"], true)
      |> put_in(["applied_gate_values", Gates.transition_readiness_required_gate_key()], true)
      |> put_in(["applied_gate_values", "review_handoff_required"], true)

    assert {:error, %{errors: errors}} = OperatorApplyRecord.validate(record)

    assert Enum.any?(errors, &(&1.code == "automatic_apply"))
    assert Enum.any?(errors, &(&1.code == "legacy_gate_name"))
    assert Enum.any?(errors, &(&1.code == "applied_gate_values_mismatch"))
  end

  test "requires every plan step and rollback readiness" do
    [_removed | remaining] = valid_record()["completed_operator_steps"]

    record =
      valid_record()
      |> Map.put("completed_operator_steps", remaining)
      |> put_in(["rollback_readiness", "verified"], false)
      |> put_in(["rollback_readiness", "disable_gates"], [Gates.enabled_gate_key()])

    assert {:error, %{errors: errors}} = OperatorApplyRecord.validate(record)

    assert Enum.any?(errors, &(&1.code == "missing_operator_step" and &1.step_id == "confirm_change_ticket"))
    assert Enum.any?(errors, &(&1.code == "rollback_not_ready"))
    assert Enum.any?(errors, &(&1.code == "missing_rollback_gate" and &1.gate == Gates.transition_readiness_required_gate_key()))
  end

  test "rejects duplicate and plan-external completed steps" do
    [first | _rest] = steps = valid_record()["completed_operator_steps"]

    record =
      valid_record()
      |> Map.put("completed_operator_steps", [
        first,
        first,
        %{
          "id" => "apply_unreviewed_gate",
          "status" => "completed",
          "completed_by" => "release-operator",
          "completed_at" => "2026-06-25T00:30:00Z"
        }
        | steps
      ])

    assert {:error, %{errors: errors}} = OperatorApplyRecord.validate(record)

    assert Enum.any?(errors, &(&1.code == "duplicate_operator_step" and &1.step_id == first["id"]))
    assert Enum.any?(errors, &(&1.code == "unexpected_operator_step" and &1.step_id == "apply_unreviewed_gate"))
  end

  test "requires observation start to match the apply plan" do
    record =
      valid_record()
      |> put_in(["observation_start", "started"], false)
      |> put_in(["observation_start", "observation_window", "duration_days"], 1)

    assert {:error, %{errors: errors}} = OperatorApplyRecord.validate(record)

    assert Enum.any?(errors, &(&1.code == "observation_not_started"))
    assert Enum.any?(errors, &(&1.code == "observation_window_mismatch"))
  end

  defp valid_record do
    plan = ready_apply_plan()

    %{
      "apply_record_id" => "apply-record-tapd-cnb-shadow",
      "operator_apply_plan" => plan,
      "apply_metadata" => %{
        "applied_by" => "release-operator",
        "applied_at" => "2026-06-25T00:30:00Z",
        "change_ticket" => "CHANGE-123",
        "operator_confirmation" => true,
        "automatic_apply" => false
      },
      "applied_scope" => plan["scope"],
      "applied_gate_values" => plan["gate_values"],
      "completed_operator_steps" => completed_steps(plan),
      "rollback_readiness" => %{
        "owner" => "workflow-runtime",
        "disable_gates" => [
          Gates.transition_readiness_required_gate_key(),
          Gates.enabled_gate_key()
        ],
        "verified" => true
      },
      "observation_start" => %{
        "started" => true,
        "observation_window" => plan["observation_window"]
      }
    }
  end

  defp completed_steps(plan) do
    Enum.map(plan["operator_steps"], fn step ->
      %{
        "id" => step["id"],
        "status" => "completed",
        "completed_by" => "release-operator",
        "completed_at" => "2026-06-25T00:30:00Z"
      }
    end)
  end

  defp ready_apply_plan do
    %{
      "schema" => "coding_pr_delivery.production_operator_apply_plan.v1",
      "status" => "ready_for_operator_apply",
      "enablement_request_id" => "enablement-tapd-cnb-shadow",
      "profile_instance_id" => "coding-pr-delivery-production",
      "review_packet_id" => "review-packet-tapd-cnb-shadow",
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
      "activation_control" => %{
        "change_ticket" => "CHANGE-123",
        "requires_operator_apply" => true,
        "applies_immediately" => false
      },
      "operator_steps" => [
        %{"id" => "confirm_change_ticket"},
        %{"id" => "verify_scope"},
        %{"id" => "apply_gate_values"},
        %{"id" => "start_observation_window"},
        %{"id" => "record_operator_apply"}
      ],
      "rollback_steps" => [
        %{"id" => "disable_transition_readiness", "gate" => Gates.transition_readiness_required_gate_key(), "owner" => "workflow-runtime"},
        %{"id" => "disable_configured_gates", "disable_gates" => [Gates.transition_readiness_required_gate_key(), Gates.enabled_gate_key()]}
      ],
      "blockers" => [],
      "does_not_apply_settings" => true,
      "requires_operator_confirmation" => true,
      "can_apply_automatically" => false
    }
  end
end
