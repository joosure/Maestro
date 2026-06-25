defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatusTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatus
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "accepts passed observation status for a valid operator apply record" do
    assert {:ok, status} = ObservationStatus.validate(valid_status())

    assert status["schema"] == "coding_pr_delivery.production_observation_status.v1"
    assert status["observation_status_id"] == "observation-tapd-cnb-shadow"
    assert status["status"] == "passed"
    assert status["profile_instance_id"] == "coding-pr-delivery-production"
    assert status["apply_record_id"] == "apply-record-tapd-cnb-shadow"
    assert status["records_observation_only"] == true
    assert status["does_not_enable_production"] == true
  end

  test "requires exact success-criteria coverage and matching summary status" do
    [first | _rest] = valid_status()["criteria_results"]

    status =
      valid_status()
      |> Map.put("status", "passed")
      |> Map.put("criteria_results", [
        %{first | "status" => "failed"},
        first,
        %{
          "criterion" => "unreviewed criterion",
          "status" => "passed",
          "observed_at" => "2026-06-25T01:00:00Z",
          "evidence_files" => ["evidence/observation/unreviewed.md"]
        }
      ])

    assert {:error, %{errors: errors}} = ObservationStatus.validate(status)

    assert Enum.any?(errors, &(&1.code == "observation_status_mismatch" and &1.expected_status == "failed"))
    assert Enum.any?(errors, &(&1.code == "missing_criterion_result" and &1.criterion == "zero shadow isolation violations"))
    assert Enum.any?(errors, &(&1.code == "duplicate_criterion_result" and &1.criterion == "zero canonical writes"))
    assert Enum.any?(errors, &(&1.code == "unexpected_criterion_result" and &1.criterion == "unreviewed criterion"))
  end

  test "rejects shadow observations that mutate canonical surfaces or change the window" do
    status =
      valid_status()
      |> put_in(["observation_window", "duration_days"], 1)
      |> put_in(["no_write_observation", "production_write_performed"], true)
      |> put_in(["no_write_observation", "canonical_surface_mutated"], true)

    assert {:error, %{errors: errors}} = ObservationStatus.validate(status)

    assert Enum.any?(errors, &(&1.code == "observation_window_mismatch"))
    assert Enum.any?(errors, &(&1.code == "shadow_production_write"))
    assert Enum.any?(errors, &(&1.code == "shadow_canonical_surface_mutated"))
  end

  test "rejects invalid nested operator apply records" do
    status =
      valid_status()
      |> put_in(["operator_apply_record", "apply_metadata", "automatic_apply"], true)

    assert {:error, %{errors: errors}} = ObservationStatus.validate(status)

    assert Enum.any?(
             errors,
             &(&1.code == "automatic_apply" and &1.path == ["operator_apply_record", "apply_metadata", "automatic_apply"])
           )
  end

  test "exposes observation status validation through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_observation_status.v1"}} =
             ProductionProfile.validate_observation_status(valid_status())
  end

  defp valid_status do
    record = valid_apply_record()
    window = record["observation_start"]["observation_window"]

    %{
      "observation_status_id" => "observation-tapd-cnb-shadow",
      "operator_apply_record" => record,
      "observed_by" => "release-operator",
      "observed_at" => "2026-06-25T01:00:00Z",
      "status" => "passed",
      "observation_window" => window,
      "criteria_results" =>
        Enum.map(window["success_criteria"], fn criterion ->
          %{
            "criterion" => criterion,
            "status" => "passed",
            "observed_at" => "2026-06-25T01:00:00Z",
            "evidence_files" => ["evidence/observation/#{String.replace(criterion, " ", "-")}.md"]
          }
        end),
      "no_write_observation" => %{
        "production_write_performed" => false,
        "canonical_surface_mutated" => false
      }
    }
  end

  defp valid_apply_record do
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
