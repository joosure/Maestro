defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyPlan do
  @moduledoc """
  Builds a bounded operator apply plan for accepted enablement requests.

  The plan is an instruction projection for human operators. It names the
  reviewed scope, gate values, observation window, and rollback checks that must
  be applied outside this validator. It never writes configuration, calls
  providers, mutates workflow state, or enables production gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequest
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @schema "coding_pr_delivery.production_operator_apply_plan.v1"

  @spec build(map()) :: {:ok, map()}
  def build(request) when is_map(request) do
    case EnablementRequest.validate(request) do
      {:ok, normalized_request} ->
        {:ok, ready_plan(normalized_request)}

      {:error, reason} ->
        {:ok, blocked_plan(request, reason)}
    end
  end

  def build(request) do
    {:ok,
     %{
       "schema" => @schema,
       "status" => "blocked",
       "enablement_request_id" => nil,
       "profile_instance_id" => nil,
       "review_packet_id" => nil,
       "operator_steps" => [],
       "rollback_steps" => [],
       "blockers" => [blocker(%{code: "invalid_type", path: [], message: "Enablement request must be an object."})],
       "does_not_apply_settings" => true,
       "requires_operator_confirmation" => true,
       "can_apply_automatically" => false,
       "input_type" => inspect(request)
     }}
  end

  defp ready_plan(request) do
    %{
      "schema" => @schema,
      "status" => "ready_for_operator_apply",
      "enablement_request_id" => Map.get(request, "enablement_request_id"),
      "profile_instance_id" => Map.get(request, "profile_instance_id"),
      "review_packet_id" => Map.get(request, "review_packet_id"),
      "scope" => Map.get(request, "scope"),
      "gate_values" => Map.get(request, "gate_values"),
      "observation_window" => Map.get(request, "observation_window"),
      "activation_control" => Map.get(request, "activation_control"),
      "operator_steps" => operator_steps(request),
      "rollback_steps" => rollback_steps(request),
      "blockers" => [],
      "does_not_apply_settings" => true,
      "requires_operator_confirmation" => true,
      "can_apply_automatically" => false
    }
  end

  defp blocked_plan(request, reason) do
    %{
      "schema" => @schema,
      "status" => "blocked",
      "enablement_request_id" => value_at(request, ["enablement_request_id"]),
      "profile_instance_id" => value_at(request, ["review_decision", "profile_instance_id"]),
      "review_packet_id" => value_at(request, ["review_decision", "review_packet_id"]),
      "operator_steps" => [],
      "rollback_steps" => [],
      "blockers" => blockers(reason),
      "does_not_apply_settings" => true,
      "requires_operator_confirmation" => true,
      "can_apply_automatically" => false
    }
  end

  defp operator_steps(request) do
    [
      %{
        "id" => "confirm_change_ticket",
        "title" => "Confirm change ticket and operator ownership.",
        "status" => "pending_operator_apply",
        "change_ticket" => value_at(request, ["activation_control", "change_ticket"])
      },
      %{
        "id" => "verify_scope",
        "title" => "Verify provider entries, repositories, environment, and side-effect mode.",
        "status" => "pending_operator_apply",
        "scope" => Map.get(request, "scope")
      },
      %{
        "id" => "apply_gate_values",
        "title" => "Apply reviewed gate values through the production configuration path.",
        "status" => "pending_operator_apply",
        "gate_values" => Map.get(request, "gate_values")
      },
      %{
        "id" => "start_observation_window",
        "title" => "Start the approved observation window and success criteria tracking.",
        "status" => "pending_operator_apply",
        "observation_window" => Map.get(request, "observation_window")
      },
      %{
        "id" => "record_operator_apply",
        "title" => "Record operator confirmation after the external apply completes.",
        "status" => "pending_operator_apply",
        "requires_operator_confirmation" => true
      }
    ]
  end

  defp rollback_steps(request) do
    rollback = Map.get(request, "rollback", %{})

    [
      %{
        "id" => "disable_transition_readiness",
        "title" => "Disable the external transition readiness gate if rollback is needed.",
        "status" => "available_before_apply",
        "gate" => Gates.transition_readiness_required_gate_key(),
        "owner" => Map.get(rollback, "owner")
      },
      %{
        "id" => "disable_configured_gates",
        "title" => "Disable every reviewed rollback gate.",
        "status" => "available_before_apply",
        "disable_gates" => Map.get(rollback, "disable_gates", [])
      }
    ]
  end

  defp blockers(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &blocker/1)
  defp blockers(%{"errors" => errors}) when is_list(errors), do: Enum.map(errors, &blocker/1)
  defp blockers(reason), do: [blocker(reason)]

  defp blocker(error) when is_map(error) do
    %{
      "code" => Map.get(error, :code) || Map.get(error, "code") || "invalid",
      "path" => Map.get(error, :path) || Map.get(error, "path") || [],
      "message" => Map.get(error, :message) || Map.get(error, "message") || "Enablement request is invalid."
    }
  end

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
