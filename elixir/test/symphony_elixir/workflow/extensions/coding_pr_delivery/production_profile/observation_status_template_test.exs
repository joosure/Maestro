defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatusTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatus
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatusTemplate
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "builds an observation-status template from a valid operator apply record" do
    apply_record = valid_apply_record()

    assert {:ok, template} = ObservationStatusTemplate.build(apply_record)

    assert template["schema"] == "coding_pr_delivery.production_observation_status_template.v1"
    assert template["completed_packet_schema"] == "coding_pr_delivery.production_observation_status.v1"
    assert template["template_authority"] == "observation_status_shape_only"
    assert template["records_observation_only"] == true
    assert template["does_not_enable_production"] == true
    assert template["apply_record_id"] == "apply-record-tapd-cnb-shadow"
    assert template["status_options"] == ["in_progress", "passed", "failed"]

    field_template = template["observation_status_field_template"]

    assert field_template["operator_apply_record"] == apply_record
    assert field_template["status"] == "in_progress"
    assert field_template["observation_window"] == apply_record["observation_start"]["observation_window"]
    assert length(field_template["criteria_results"]) == 2

    assert field_template["no_write_observation"] == %{
             "production_write_performed" => false,
             "canonical_surface_mutated" => false
           }

    assert "no_write_observation.production_write_performed" in template["fields_to_complete"]
  end

  test "field template can be completed into a valid observation status" do
    assert {:ok, template} = ObservationStatusTemplate.build(valid_apply_record())

    status =
      template["observation_status_field_template"]
      |> Map.merge(%{
        "observation_status_id" => "observation-tapd-cnb-shadow",
        "observed_by" => "release-operator",
        "observed_at" => "2026-06-25T01:00:00Z",
        "status" => "passed"
      })
      |> Map.update!("criteria_results", fn results ->
        Enum.map(results, fn result ->
          result
          |> Map.put("status", "passed")
          |> Map.put("observed_at", "2026-06-25T01:00:00Z")
          |> Map.put("evidence_files", ["evidence/observation/#{String.replace(result["criterion"], " ", "-")}.md"])
        end)
      end)

    assert {:ok, %{"schema" => "coding_pr_delivery.production_observation_status.v1"}} =
             ObservationStatus.validate(status)
  end

  test "rejects invalid operator apply records before building a template" do
    invalid_record =
      valid_apply_record()
      |> put_in(["apply_metadata", "automatic_apply"], true)

    assert {:error, %{code: "coding_pr_delivery_operator_apply_record_invalid", errors: errors}} =
             ObservationStatusTemplate.build(invalid_record)

    assert Enum.any?(errors, &(&1.code == "automatic_apply"))
  end

  test "exposes observation status templates through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_observation_status_template.v1"}} =
             ProductionProfile.observation_status_template(valid_apply_record())
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
