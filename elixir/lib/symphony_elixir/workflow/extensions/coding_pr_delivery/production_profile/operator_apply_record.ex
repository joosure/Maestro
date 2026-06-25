defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecord do
  @moduledoc """
  Admission checks for external operator apply records.

  The record proves that a human operator applied the previously reviewed apply
  plan through an external configuration path. This module validates the record
  metadata only; it does not apply settings, call providers, mutate workflow
  state, or enable production gates.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @schema "coding_pr_delivery.production_operator_apply_record.v1"
  @error_code "coding_pr_delivery_operator_apply_record_invalid"
  @plan_schema "coding_pr_delivery.production_operator_apply_plan.v1"

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate(map()) :: validation_result()
  def validate(record) when is_map(record) do
    plan = value_at(record, ["operator_apply_plan"])
    metadata = value_at(record, ["apply_metadata"])

    errors =
      []
      |> collect_required_string(record, ["apply_record_id"])
      |> collect_plan(plan)
      |> collect_apply_metadata(metadata, plan)
      |> collect_applied_scope(record, plan)
      |> collect_applied_gate_values(record, plan)
      |> collect_completed_steps(record, plan)
      |> collect_rollback_readiness(record, plan)
      |> collect_observation_start(record, plan)

    if errors == [] do
      {:ok, normalize(record, plan)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate(_record) do
    {:error, invalid([issue("invalid_type", [], "Operator apply record must be an object.")])}
  end

  defp collect_plan(errors, plan) when is_map(plan) do
    blockers = value_at(plan, ["blockers"])

    errors
    |> maybe_add(
      value_at(plan, ["schema"]) != @plan_schema,
      issue("invalid_operator_apply_plan_schema", ["operator_apply_plan", "schema"], "Operator apply plan schema is invalid.")
    )
    |> maybe_add(
      value_at(plan, ["status"]) != "ready_for_operator_apply",
      issue("operator_apply_plan_not_ready", ["operator_apply_plan", "status"], "Operator apply record requires a ready apply plan.")
    )
    |> maybe_add(
      blockers != [],
      issue("operator_apply_plan_blocked", ["operator_apply_plan", "blockers"], "Operator apply record requires an apply plan with no blockers.")
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

  defp collect_plan(errors, _plan) do
    errors ++ [issue("required_field_missing", ["operator_apply_plan"], "Operator apply plan must be an object.")]
  end

  defp collect_apply_metadata(errors, metadata, plan) when is_map(metadata) do
    applied_at = value_at(metadata, ["applied_at"])
    expected_ticket = value_at(plan, ["activation_control", "change_ticket"])

    errors
    |> collect_required_string(metadata, ["apply_metadata", "applied_by"])
    |> collect_required_string(metadata, ["apply_metadata", "applied_at"])
    |> collect_required_string(metadata, ["apply_metadata", "change_ticket"])
    |> maybe_add(
      non_empty_string?(applied_at) and not valid_datetime?(applied_at),
      issue("invalid_timestamp", ["apply_metadata", "applied_at"], "Applied-at timestamp must be ISO8601.")
    )
    |> maybe_add(
      value_at(metadata, ["change_ticket"]) != expected_ticket,
      issue("change_ticket_mismatch", ["apply_metadata", "change_ticket"], "Apply record change ticket must match the apply plan.")
    )
    |> maybe_add(
      value_at(metadata, ["operator_confirmation"]) != true,
      issue("missing_operator_confirmation", ["apply_metadata", "operator_confirmation"], "Operator apply record must include explicit confirmation.")
    )
    |> maybe_add(
      value_at(metadata, ["automatic_apply"]) != false,
      issue("automatic_apply", ["apply_metadata", "automatic_apply"], "Operator apply record must not be automatic.")
    )
  end

  defp collect_apply_metadata(errors, _metadata, _plan) do
    errors ++ [issue("required_field_missing", ["apply_metadata"], "Apply metadata must be an object.")]
  end

  defp collect_applied_scope(errors, record, plan) do
    applied_scope = value_at(record, ["applied_scope"])
    expected_scope = value_at(plan, ["scope"])

    errors
    |> collect_required_map(record, ["applied_scope"])
    |> maybe_add(
      is_map(applied_scope) and applied_scope != expected_scope,
      issue("applied_scope_mismatch", ["applied_scope"], "Applied scope must match the reviewed apply plan scope.")
    )
  end

  defp collect_applied_gate_values(errors, record, plan) do
    gate_values = value_at(record, ["applied_gate_values"])
    expected_gate_values = value_at(plan, ["gate_values"])
    transition_gate = Gates.transition_readiness_required_gate_key()

    errors
    |> collect_required_map(record, ["applied_gate_values"])
    |> maybe_add(
      is_map(gate_values) and Map.has_key?(gate_values, "review_handoff_required"),
      issue("legacy_gate_name", ["applied_gate_values", "review_handoff_required"], "Legacy review_handoff_required gate must not be applied.")
    )
    |> maybe_add(
      is_map(gate_values) and not Map.has_key?(gate_values, transition_gate),
      issue("missing_transition_readiness_gate", ["applied_gate_values"], "Applied gate values must include the external transition readiness gate.")
    )
    |> maybe_add(
      is_map(gate_values) and gate_values != expected_gate_values,
      issue("applied_gate_values_mismatch", ["applied_gate_values"], "Applied gate values must match the reviewed apply plan.")
    )
  end

  defp collect_completed_steps(errors, record, plan) do
    steps = value_at(record, ["completed_operator_steps"])

    cond do
      not is_list(steps) or steps == [] ->
        errors ++ [issue("required_field_missing", ["completed_operator_steps"], "Completed operator steps must be a non-empty array.")]

      true ->
        expected_ids = plan |> value_at(["operator_steps"]) |> expected_step_ids()

        errors ++
          completed_step_errors(steps) ++
          completed_step_coverage_errors(steps, expected_ids)
    end
  end

  defp completed_step_errors(steps) do
    steps
    |> Enum.with_index()
    |> Enum.flat_map(fn {step, index} -> completed_step_errors(step, index) end)
  end

  defp completed_step_errors(step, index) when is_map(step) do
    path = ["completed_operator_steps", index]
    completed_at = value_at(step, ["completed_at"])

    []
    |> collect_required_string(step, path ++ ["id"])
    |> collect_required_string(step, path ++ ["completed_by"])
    |> collect_required_string(step, path ++ ["completed_at"])
    |> maybe_add(
      non_empty_string?(completed_at) and not valid_datetime?(completed_at),
      issue("invalid_timestamp", path ++ ["completed_at"], "Completed-at timestamp must be ISO8601.")
    )
    |> maybe_add(
      value_at(step, ["status"]) != "completed",
      issue("operator_step_not_completed", path ++ ["status"], "Operator step status must be completed.")
    )
  end

  defp completed_step_errors(_step, index) do
    [issue("invalid_type", ["completed_operator_steps", index], "Completed operator step must be an object.")]
  end

  defp completed_step_coverage_errors(steps, expected_ids) do
    observed_ids =
      steps
      |> Enum.filter(&is_map/1)
      |> Enum.map(&value_at(&1, ["id"]))
      |> Enum.filter(&non_empty_string?/1)

    observed_counts = Enum.frequencies(observed_ids)

    missing =
      expected_ids
      |> Enum.reject(&(&1 in observed_ids))
      |> Enum.map(fn step_id ->
        issue("missing_operator_step", ["completed_operator_steps"], "Every apply plan operator step must be completed.", %{step_id: step_id})
      end)

    duplicate =
      observed_counts
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {step_id, _count} ->
        issue("duplicate_operator_step", ["completed_operator_steps"], "Operator step must not be recorded more than once.", %{step_id: step_id})
      end)

    unexpected =
      observed_ids
      |> Enum.reject(&(&1 in expected_ids))
      |> Enum.map(fn step_id ->
        issue("unexpected_operator_step", ["completed_operator_steps"], "Completed operator step must be present in the apply plan.", %{step_id: step_id})
      end)

    missing ++ duplicate ++ unexpected
  end

  defp collect_rollback_readiness(errors, record, plan) do
    readiness = value_at(record, ["rollback_readiness"])
    expected_gates = value_at(plan, ["rollback_steps"]) |> rollback_gates()
    disable_gates = value_at(readiness, ["disable_gates"])

    errors
    |> collect_required_map(record, ["rollback_readiness"])
    |> collect_required_string(readiness, ["rollback_readiness", "owner"])
    |> collect_string_list(readiness, ["rollback_readiness", "disable_gates"], "Rollback readiness disable gates must be a non-empty string array.")
    |> maybe_add(
      value_at(readiness, ["verified"]) != true,
      issue("rollback_not_ready", ["rollback_readiness", "verified"], "Rollback readiness must be verified.")
    )
    |> collect_missing_rollback_gates(disable_gates, expected_gates)
  end

  defp collect_missing_rollback_gates(errors, disable_gates, expected_gates) when is_list(disable_gates) do
    expected_gates
    |> Enum.reject(&(&1 in disable_gates))
    |> Enum.map(fn gate ->
      issue("missing_rollback_gate", ["rollback_readiness", "disable_gates"], "Rollback readiness must include every apply-plan rollback gate.", %{gate: gate})
    end)
    |> then(&(errors ++ &1))
  end

  defp collect_missing_rollback_gates(errors, _disable_gates, _expected_gates), do: errors

  defp collect_observation_start(errors, record, plan) do
    observation = value_at(record, ["observation_start"])
    expected_window = value_at(plan, ["observation_window"])

    errors
    |> collect_required_map(record, ["observation_start"])
    |> maybe_add(
      value_at(observation, ["started"]) != true,
      issue("observation_not_started", ["observation_start", "started"], "Observation window must be started.")
    )
    |> maybe_add(
      value_at(observation, ["observation_window"]) != expected_window,
      issue("observation_window_mismatch", ["observation_start", "observation_window"], "Observation window must match the apply plan.")
    )
  end

  defp normalize(record, plan) do
    %{
      "schema" => @schema,
      "apply_record_id" => value_at(record, ["apply_record_id"]),
      "enablement_request_id" => value_at(plan, ["enablement_request_id"]),
      "profile_instance_id" => value_at(plan, ["profile_instance_id"]),
      "review_packet_id" => value_at(plan, ["review_packet_id"]),
      "applied_scope" => value_at(record, ["applied_scope"]),
      "applied_gate_values" => value_at(record, ["applied_gate_values"]),
      "completed_operator_step_ids" => completed_step_ids(record),
      "rollback_readiness" => value_at(record, ["rollback_readiness"]),
      "observation_start" => value_at(record, ["observation_start"]),
      "does_not_apply_settings" => true,
      "records_external_operator_apply" => true
    }
  end

  defp expected_step_ids(steps) when is_list(steps) do
    steps
    |> Enum.map(&value_at(&1, ["id"]))
    |> Enum.filter(&non_empty_string?/1)
  end

  defp expected_step_ids(_steps), do: []

  defp rollback_gates(steps) when is_list(steps) do
    steps
    |> Enum.flat_map(fn
      %{"gate" => gate} when is_binary(gate) -> [gate]
      %{"disable_gates" => gates} when is_list(gates) -> gates
      _step -> []
    end)
    |> Enum.uniq()
  end

  defp rollback_gates(_steps), do: []

  defp completed_step_ids(record) do
    record
    |> value_at(["completed_operator_steps"])
    |> case do
      steps when is_list(steps) -> Enum.map(steps, &value_at(&1, ["id"]))
      _missing -> []
    end
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery operator apply record is invalid.",
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
