defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EnablementRequest do
  @moduledoc """
  Admission checks for production enablement requests.

  This validator accepts a bounded review-decision packet plus an explicit
  rollout scope, gate plan, observation window, rollback plan, and approval
  metadata. It validates that an enablement request is reviewable and scoped; it
  does not apply settings, call providers, mutate workflow state, or enable
  production gates.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @schema "coding_pr_delivery.production_enablement_request.v1"
  @error_code "coding_pr_delivery_enablement_request_invalid"
  @review_decision_schema "coding_pr_delivery.production_review_decision.v1"
  @side_effect_modes ["read_only", "shadow_no_write", "review_handoff_write", "ready_to_land_write"]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate(map()) :: validation_result()
  def validate(request) when is_map(request) do
    review_decision = value_at(request, ["review_decision"])
    scope = value_at(request, ["scope"])
    gate_values = value_at(request, ["gate_values"])
    requested_mode = value_at(scope, ["side_effect_mode"])
    selected_entry_ids = value_at(scope, ["provider_matrix_entry_ids"])

    errors =
      []
      |> collect_required_string(request, ["enablement_request_id"])
      |> collect_required_string(request, ["requested_by"])
      |> collect_requested_at(request)
      |> collect_review_decision(review_decision)
      |> collect_scope(scope, review_decision)
      |> collect_gate_values(gate_values, requested_mode)
      |> collect_observation_window(request)
      |> collect_rollback(request)
      |> collect_non_claim_acknowledgement(request, review_decision, selected_entry_ids)
      |> collect_approvals(request)
      |> collect_activation_control(request)

    if errors == [] do
      {:ok, normalize(request)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate(_request) do
    {:error, invalid([issue("invalid_type", [], "Enablement request must be an object.")])}
  end

  defp collect_requested_at(errors, request) do
    requested_at = value_at(request, ["requested_at"])

    errors
    |> collect_required_string(request, ["requested_at"])
    |> maybe_add(
      non_empty_string?(requested_at) and not valid_datetime?(requested_at),
      issue("invalid_timestamp", ["requested_at"], "Requested-at timestamp must be ISO8601.")
    )
  end

  defp collect_review_decision(errors, decision) when is_map(decision) do
    blockers = value_at(decision, ["blockers"])

    errors
    |> maybe_add(
      value_at(decision, ["schema"]) != @review_decision_schema,
      issue("invalid_review_decision_schema", ["review_decision", "schema"], "Review decision schema is invalid.")
    )
    |> maybe_add(
      value_at(decision, ["status"]) != "ready_for_approval",
      issue("review_decision_not_ready", ["review_decision", "status"], "Enablement requires a ready review decision.")
    )
    |> maybe_add(
      blockers != [],
      issue("review_decision_blocked", ["review_decision", "blockers"], "Enablement requires a review decision with no blockers.")
    )
    |> maybe_add(
      value_at(decision, ["does_not_enable_production"]) != true,
      issue("review_decision_side_effect_boundary", ["review_decision", "does_not_enable_production"], "Review decision must be non-mutating.")
    )
    |> maybe_add(
      value_at(decision, ["raw_evidence_payload_included"]) != false,
      issue("raw_evidence_payload_present", ["review_decision", "raw_evidence_payload_included"], "Review decision must not include raw evidence payloads.")
    )
    |> maybe_add(
      not non_empty_string?(value_at(decision, ["profile_instance_id"])),
      issue("required_field_missing", ["review_decision", "profile_instance_id"], "Review decision must name the profile instance.")
    )
    |> maybe_add(
      not is_list(value_at(decision, ["provider_entries"])) or value_at(decision, ["provider_entries"]) == [],
      issue("required_field_missing", ["review_decision", "provider_entries"], "Review decision must include provider entries.")
    )
  end

  defp collect_review_decision(errors, _decision) do
    errors ++ [issue("required_field_missing", ["review_decision"], "Review decision must be an object.")]
  end

  defp collect_scope(errors, scope, review_decision) when is_map(scope) do
    requested_ids = value_at(scope, ["provider_matrix_entry_ids"])
    requested_mode = value_at(scope, ["side_effect_mode"])
    decision_entries = decision_provider_entries(review_decision)
    decision_entry_ids = Enum.map(decision_entries, &Map.get(&1, "entry_id"))
    selected_entries = Enum.filter(decision_entries, &(Map.get(&1, "entry_id") in List.wrap(requested_ids)))

    errors
    |> collect_required_string(scope, ["scope", "environment"])
    |> maybe_add(
      value_at(scope, ["environment"]) not in ["staging", "production"],
      issue("invalid_environment", ["scope", "environment"], "Environment must be staging or production.")
    )
    |> collect_string_list(scope, ["scope", "repositories"], "Repository scope must be a non-empty string array.")
    |> collect_string_list(scope, ["scope", "provider_matrix_entry_ids"], "Provider entry scope must be a non-empty string array.")
    |> collect_required_string(scope, ["scope", "side_effect_mode"])
    |> maybe_add(
      non_empty_string?(requested_mode) and requested_mode not in @side_effect_modes,
      issue("invalid_side_effect_mode", ["scope", "side_effect_mode"], "Requested side-effect mode is unsupported.")
    )
    |> collect_unknown_provider_entries(requested_ids, decision_entry_ids)
    |> collect_mode_escalation(requested_mode, selected_entries)
  end

  defp collect_scope(errors, _scope, _review_decision) do
    errors ++ [issue("required_field_missing", ["scope"], "Enablement scope must be an object.")]
  end

  defp collect_unknown_provider_entries(errors, requested_ids, decision_entry_ids) when is_list(requested_ids) do
    requested_ids
    |> Enum.reject(&(&1 in decision_entry_ids))
    |> Enum.map(fn entry_id ->
      issue("unknown_provider_matrix_entry", ["scope", "provider_matrix_entry_ids"], "Requested provider entry is not present in the ready review decision.", %{provider_matrix_entry_id: entry_id})
    end)
    |> then(&(errors ++ &1))
  end

  defp collect_unknown_provider_entries(errors, _requested_ids, _decision_entry_ids), do: errors

  defp collect_mode_escalation(errors, requested_mode, selected_entries) when is_list(selected_entries) do
    selected_entries
    |> Enum.reject(&(Map.get(&1, "side_effect_mode") == requested_mode))
    |> Enum.map(fn entry ->
      issue("side_effect_mode_escalation", ["scope", "side_effect_mode"], "Enablement request must not broaden a provider entry's reviewed side-effect mode.", %{
        provider_matrix_entry_id: Map.get(entry, "entry_id"),
        reviewed_side_effect_mode: Map.get(entry, "side_effect_mode"),
        requested_side_effect_mode: requested_mode
      })
    end)
    |> then(&(errors ++ &1))
  end

  defp collect_gate_values(errors, gate_values, requested_mode) when is_map(gate_values) do
    transition_gate = Gates.transition_readiness_required_gate_key()

    errors
    |> maybe_add(
      Map.has_key?(gate_values, "review_handoff_required"),
      issue("legacy_gate_name", ["gate_values", "review_handoff_required"], "Legacy review_handoff_required gate must not be used.")
    )
    |> maybe_add(
      not Map.has_key?(gate_values, transition_gate),
      issue("missing_transition_readiness_gate", ["gate_values"], "Gate values must include the external transition readiness gate.")
    )
    |> maybe_add(
      Map.has_key?(gate_values, transition_gate) and not is_boolean(Map.get(gate_values, transition_gate)),
      issue("invalid_gate_value", ["gate_values", transition_gate], "Transition readiness gate must be a boolean.")
    )
    |> maybe_add(
      requested_mode == "ready_to_land_write" and Map.get(gate_values, transition_gate) != true,
      issue("ready_to_land_without_transition_gate", ["gate_values", transition_gate], "Ready-to-land enablement requires transition readiness enforcement.")
    )
  end

  defp collect_gate_values(errors, _gate_values, _requested_mode) do
    errors ++ [issue("required_field_missing", ["gate_values"], "Gate values must be an object.")]
  end

  defp collect_observation_window(errors, request) do
    window = value_at(request, ["observation_window"])
    days = value_at(window, ["duration_days"])

    errors
    |> collect_required_map(request, ["observation_window"])
    |> maybe_add(
      not is_integer(days) or days <= 0,
      issue("invalid_observation_window", ["observation_window", "duration_days"], "Observation window duration must be a positive integer.")
    )
    |> collect_string_list(window, ["observation_window", "success_criteria"], "Observation success criteria must be a non-empty string array.")
  end

  defp collect_rollback(errors, request) do
    rollback = value_at(request, ["rollback"])
    gates = value_at(rollback, ["disable_gates"])
    transition_gate = Gates.transition_readiness_required_gate_key()

    errors
    |> collect_required_map(request, ["rollback"])
    |> collect_required_string(rollback, ["rollback", "owner"])
    |> collect_string_list(rollback, ["rollback", "disable_gates"], "Rollback disable gates must be a non-empty string array.")
    |> maybe_add(
      is_list(gates) and transition_gate not in gates,
      issue("missing_rollback_gate", ["rollback", "disable_gates"], "Rollback must include the transition readiness gate.")
    )
    |> maybe_add(
      value_at(rollback, ["verified"]) != true,
      issue("rollback_not_verified", ["rollback", "verified"], "Rollback must be verified before enablement is requested.")
    )
  end

  defp collect_non_claim_acknowledgement(errors, request, review_decision, requested_ids) do
    acknowledged = value_at(request, ["acknowledged_non_claims"])
    expected = expected_non_claims(review_decision, requested_ids)

    errors =
      collect_string_list(errors, request, ["acknowledged_non_claims"], "Acknowledged non-claims must be a non-empty string array.")

    if is_list(acknowledged) do
      expected
      |> Enum.reject(&(&1 in acknowledged))
      |> Enum.map(fn non_claim ->
        issue("missing_non_claim_acknowledgement", ["acknowledged_non_claims"], "Enablement request must acknowledge every selected provider non-claim.", %{non_claim: non_claim})
      end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp collect_approvals(errors, request) do
    approvals = value_at(request, ["approvals"])

    cond do
      not is_list(approvals) or approvals == [] ->
        errors ++ [issue("required_field_missing", ["approvals"], "Approvals must be a non-empty array.")]

      true ->
        errors ++
          (approvals
           |> Enum.with_index()
           |> Enum.flat_map(fn {approval, index} -> approval_errors(approval, index) end))
    end
  end

  defp approval_errors(approval, index) when is_map(approval) do
    path = ["approvals", index]
    approved_at = value_at(approval, ["approved_at"])

    []
    |> collect_required_string(approval, path ++ ["role"])
    |> collect_required_string(approval, path ++ ["owner"])
    |> collect_required_string(approval, path ++ ["approved_at"])
    |> maybe_add(
      non_empty_string?(approved_at) and not valid_datetime?(approved_at),
      issue("invalid_timestamp", path ++ ["approved_at"], "Approved-at timestamp must be ISO8601.")
    )
    |> maybe_add(
      value_at(approval, ["decision"]) != "approved",
      issue("approval_not_approved", path ++ ["decision"], "Enablement approval decision must be approved.")
    )
  end

  defp approval_errors(_approval, index) do
    [issue("invalid_type", ["approvals", index], "Approval must be an object.")]
  end

  defp collect_activation_control(errors, request) do
    control = value_at(request, ["activation_control"])

    errors
    |> collect_required_map(request, ["activation_control"])
    |> collect_required_string(control, ["activation_control", "change_ticket"])
    |> maybe_add(
      value_at(control, ["requires_operator_apply"]) != true,
      issue("missing_operator_apply", ["activation_control", "requires_operator_apply"], "Enablement request must require an explicit operator apply.")
    )
    |> maybe_add(
      value_at(control, ["applies_immediately"]) != false,
      issue("immediate_activation", ["activation_control", "applies_immediately"], "Enablement admission must not apply changes immediately.")
    )
  end

  defp decision_provider_entries(decision) when is_map(decision) do
    case value_at(decision, ["provider_entries"]) do
      entries when is_list(entries) -> entries
      _missing -> []
    end
  end

  defp decision_provider_entries(_decision), do: []

  defp expected_non_claims(decision, requested_ids) when is_list(requested_ids) do
    decision
    |> decision_provider_entries()
    |> Enum.filter(&(Map.get(&1, "entry_id") in requested_ids))
    |> Enum.flat_map(&Map.get(&1, "non_claims", []))
    |> Enum.uniq()
  end

  defp expected_non_claims(_decision, _requested_ids), do: []

  defp normalize(request) do
    %{
      "schema" => @schema,
      "enablement_request_id" => value_at(request, ["enablement_request_id"]),
      "profile_instance_id" => value_at(request, ["review_decision", "profile_instance_id"]),
      "review_packet_id" => value_at(request, ["review_decision", "review_packet_id"]),
      "scope" => value_at(request, ["scope"]),
      "gate_values" => value_at(request, ["gate_values"]),
      "observation_window" => value_at(request, ["observation_window"]),
      "rollback" => value_at(request, ["rollback"]),
      "acknowledged_non_claims" => value_at(request, ["acknowledged_non_claims"]),
      "approvals" => value_at(request, ["approvals"]),
      "activation_control" => value_at(request, ["activation_control"]),
      "does_not_enable_production" => true
    }
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery enablement request is invalid.",
      errors: errors
    }
  end

  defp collect_required_string(errors, map, path) do
    maybe_add(errors, not non_empty_string?(value_at(map, [List.last(path)])), issue("required_field_missing", path, "Field must be a non-empty string."))
  end

  defp collect_required_map(errors, map, path) do
    maybe_add(errors, not is_map(value_at(map, [List.last(path)])), issue("required_field_missing", path, "Field must be an object."))
  end

  defp collect_string_list(errors, map, path, message) do
    value = value_at(map, [List.last(path)])

    maybe_add(errors, not string_list?(value) or value == [], issue("required_field_missing", path, message))
  end

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

  defp issue(code, path, message, extra \\ %{}) do
    Map.merge(
      %{
        code: code,
        path: path,
        message: message
      },
      extra
    )
  end

  defp valid_datetime?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_datetime?(_value), do: false

  defp string_list?(value) when is_list(value), do: Enum.all?(value, &non_empty_string?/1)
  defp string_list?(_value), do: false

  defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_string?(_value), do: false

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
