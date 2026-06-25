defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationDecisionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationDecision
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "projects passed observation status into a bounded reviewer decision" do
    assert {:ok, decision} = ObservationDecision.build(valid_status())

    assert decision["schema"] == "coding_pr_delivery.production_observation_decision.v1"
    assert decision["status"] == "observation_passed"
    assert decision["observation_status_id"] == "observation-tapd-cnb-shadow"
    assert decision["profile_instance_id"] == "coding-pr-delivery-production"
    assert decision["criteria_summary"] == %{"passed" => 2, "failed" => 0, "in_progress" => 0, "total" => 2}

    assert decision["no_write_observation"] == %{
             "production_write_performed" => false,
             "canonical_surface_mutated" => false
           }

    assert decision["blockers"] == []
    assert decision["records_observation_only"] == true
    assert decision["does_not_enable_production"] == true
    assert decision["raw_evidence_payload_included"] == false
  end

  test "projects failed and in-progress observations without raw evidence payloads" do
    failed_status =
      valid_status()
      |> Map.put("status", "failed")
      |> put_in(["criteria_results", Access.at(0), "status"], "failed")

    in_progress_status =
      valid_status()
      |> Map.put("status", "in_progress")
      |> put_in(["criteria_results", Access.at(0), "status"], "in_progress")

    assert {:ok, failed_decision} = ObservationDecision.build(failed_status)
    assert failed_decision["status"] == "observation_failed"
    assert failed_decision["criteria_summary"]["failed"] == 1
    assert failed_decision["raw_evidence_payload_included"] == false

    assert {:ok, in_progress_decision} = ObservationDecision.build(in_progress_status)
    assert in_progress_decision["status"] == "observation_in_progress"
    assert in_progress_decision["criteria_summary"]["in_progress"] == 1
    assert in_progress_decision["raw_evidence_payload_included"] == false
  end

  test "returns a blocked decision with bounded blockers for invalid observation status" do
    invalid_status =
      valid_status()
      |> put_in(["no_write_observation", "canonical_surface_mutated"], true)

    assert {:ok, decision} = ObservationDecision.build(invalid_status)

    assert decision["status"] == "blocked"
    assert decision["observation_status_id"] == "observation-tapd-cnb-shadow"
    assert decision["profile_instance_id"] == "coding-pr-delivery-production"
    assert decision["criteria_summary"] == %{"passed" => 2, "failed" => 0, "in_progress" => 0, "total" => 2}
    assert Enum.any?(decision["blockers"], &(&1["code"] == "shadow_canonical_surface_mutated"))
    assert decision["raw_evidence_payload_included"] == false
  end

  test "exposes observation decisions through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_observation_decision.v1"}} =
             ProductionProfile.observation_decision(valid_status())
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
