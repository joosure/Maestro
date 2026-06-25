defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecordTemplate do
  @moduledoc """
  Builds operator apply-record fill templates from ready operator apply plans.

  The template is a shape-only handoff for the external human apply path. It
  validates that the apply plan is ready and non-mutating, then projects the
  fields that must be recorded after the operator applies settings outside this
  module. It does not apply settings, call providers, mutate workflow state, or
  enable production gates.
  """

  @schema "coding_pr_delivery.production_operator_apply_record_template.v1"
  @completed_packet_schema "coding_pr_delivery.production_operator_apply_record.v1"
  @error_code "coding_pr_delivery_operator_apply_record_template_invalid"
  @plan_schema "coding_pr_delivery.production_operator_apply_plan.v1"

  @type result :: {:ok, map()} | {:error, map()}

  @spec build(map()) :: result()
  def build(plan) when is_map(plan) do
    errors = collect_plan([], plan)

    if errors == [] do
      {:ok, template(plan)}
    else
      {:error, invalid(errors)}
    end
  end

  def build(_plan) do
    {:error, invalid([issue("invalid_type", [], "Operator apply plan must be an object.")])}
  end

  defp collect_plan(errors, plan) do
    blockers = value_at(plan, ["blockers"])

    errors
    |> maybe_add(
      value_at(plan, ["schema"]) != @plan_schema,
      issue("invalid_operator_apply_plan_schema", ["operator_apply_plan", "schema"], "Operator apply plan schema is invalid.")
    )
    |> maybe_add(
      value_at(plan, ["status"]) != "ready_for_operator_apply",
      issue("operator_apply_plan_not_ready", ["operator_apply_plan", "status"], "Operator apply record template requires a ready apply plan.")
    )
    |> maybe_add(
      blockers != [],
      issue("operator_apply_plan_blocked", ["operator_apply_plan", "blockers"], "Operator apply record template requires an apply plan with no blockers.")
    )
    |> maybe_add(
      value_at(plan, ["does_not_apply_settings"]) != true,
      issue("operator_apply_plan_side_effect_boundary", ["operator_apply_plan", "does_not_apply_settings"], "Apply plan must be non-mutating.")
    )
    |> maybe_add(
      value_at(plan, ["requires_operator_confirmation"]) != true,
      issue("operator_confirmation_not_required", ["operator_apply_plan", "requires_operator_confirmation"], "Apply plan must require operator confirmation.")
    )
    |> maybe_add(
      value_at(plan, ["can_apply_automatically"]) != false,
      issue("automatic_apply_allowed", ["operator_apply_plan", "can_apply_automatically"], "Apply plan must not allow automatic apply.")
    )
  end

  defp template(plan) do
    %{
      "schema" => @schema,
      "completed_packet_schema" => @completed_packet_schema,
      "enablement_request_id" => value_at(plan, ["enablement_request_id"]),
      "profile_instance_id" => value_at(plan, ["profile_instance_id"]),
      "review_packet_id" => value_at(plan, ["review_packet_id"]),
      "template_authority" => "operator_apply_record_shape_only",
      "does_not_apply_settings" => true,
      "operator_apply_plan" => plan,
      "apply_record_field_template" => %{
        "apply_record_id" => "fill-apply-record-id",
        "operator_apply_plan" => plan,
        "apply_metadata" => %{
          "applied_by" => "fill-operator",
          "applied_at" => "fill-applied-at",
          "change_ticket" => value_at(plan, ["activation_control", "change_ticket"]),
          "operator_confirmation" => true,
          "automatic_apply" => false
        },
        "applied_scope" => value_at(plan, ["scope"]),
        "applied_gate_values" => value_at(plan, ["gate_values"]),
        "completed_operator_steps" => completed_operator_steps(plan),
        "rollback_readiness" => %{
          "owner" => rollback_owner(plan),
          "disable_gates" => rollback_gates(plan),
          "verified" => false
        },
        "observation_start" => %{
          "started" => false,
          "observation_window" => value_at(plan, ["observation_window"])
        }
      },
      "fields_to_complete" => [
        "apply_record_id",
        "apply_metadata.applied_by",
        "apply_metadata.applied_at",
        "completed_operator_steps[].completed_by",
        "completed_operator_steps[].completed_at",
        "rollback_readiness.verified",
        "observation_start.started"
      ]
    }
  end

  defp completed_operator_steps(plan) do
    plan
    |> value_at(["operator_steps"])
    |> case do
      steps when is_list(steps) ->
        Enum.map(steps, fn step ->
          %{
            "id" => value_at(step, ["id"]),
            "status" => "completed",
            "completed_by" => "fill-operator",
            "completed_at" => "fill-completed-at"
          }
        end)

      _missing ->
        []
    end
  end

  defp rollback_owner(plan) do
    plan
    |> value_at(["rollback_steps"])
    |> case do
      steps when is_list(steps) ->
        steps
        |> Enum.map(&value_at(&1, ["owner"]))
        |> Enum.find("workflow-runtime", &non_empty_string?/1)

      _missing ->
        "workflow-runtime"
    end
  end

  defp rollback_gates(plan) do
    plan
    |> value_at(["rollback_steps"])
    |> case do
      steps when is_list(steps) ->
        steps
        |> Enum.flat_map(fn
          %{"gate" => gate} when is_binary(gate) -> [gate]
          %{"disable_gates" => gates} when is_list(gates) -> gates
          _step -> []
        end)
        |> Enum.filter(&non_empty_string?/1)
        |> Enum.uniq()

      _missing ->
        []
    end
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery operator apply record template is invalid.",
      errors: errors
    }
  end

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

  defp issue(code, path, message) do
    %{
      code: code,
      path: path,
      message: message
    }
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp value_at(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, current ->
      cond do
        is_map(current) and Map.has_key?(current, key) ->
          {:cont, Map.get(current, key)}

        is_map(current) and is_atom(key) and Map.has_key?(current, Atom.to_string(key)) ->
          {:cont, Map.get(current, Atom.to_string(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp value_at(_map, _path), do: nil
end
