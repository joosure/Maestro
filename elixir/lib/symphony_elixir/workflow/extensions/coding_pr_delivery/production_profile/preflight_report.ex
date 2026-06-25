defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReport do
  @moduledoc """
  Admission checks for Phase 2 read-only provider preflight reports.

  The validator checks bounded preflight metadata only. It does not read
  evidence files, inspect provider output, call providers, mutate workflow
  state, approve production, or enable gates.
  """

  @schema "coding_pr_delivery.provider_preflight_report.v1"
  @phase2_schema "coding_pr_delivery.phase2_evidence_plan.v1"
  @error_code "coding_pr_delivery_preflight_report_invalid"
  @statuses ["passed", "blocked"]
  @raw_output_fields ["stdout", "stderr", "raw_output", "raw_payload", "environment", "env", "token"]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate(map()) :: validation_result()
  def validate(packet) when is_map(packet) do
    phase2_plan = value_at(packet, ["phase2_evidence_plan"])
    results = value_at(packet, ["provider_preflight_results"])
    expected_commands = expected_commands(phase2_plan)

    errors =
      []
      |> collect_schema(packet)
      |> collect_phase2_plan(phase2_plan)
      |> collect_results(results, expected_commands)
      |> collect_explicit_non_claims(packet)

    if errors == [] do
      {:ok, normalize(packet, expected_commands)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate(_packet) do
    {:error, invalid([issue("invalid_type", [], "Preflight report must be an object.")])}
  end

  defp collect_schema(errors, packet) do
    schema = Map.get(packet, "schema")

    cond do
      not non_empty_string?(schema) ->
        errors ++ [issue("required_field_missing", ["schema"], "Preflight report schema is required.")]

      schema != @schema ->
        errors ++ [issue("invalid_schema", ["schema"], "Preflight report schema is not supported.")]

      true ->
        errors
    end
  end

  defp collect_phase2_plan(errors, plan) do
    provider_plans = value_at(plan, ["provider_plans"])

    errors
    |> collect_required_map(%{"phase2_evidence_plan" => plan}, ["phase2_evidence_plan"])
    |> maybe_add(
      is_map(plan) and Map.get(plan, "schema") != @phase2_schema,
      issue("invalid_phase2_schema", ["phase2_evidence_plan", "schema"], "Preflight report requires a Phase 2 evidence plan.")
    )
    |> maybe_add(
      is_map(plan) and (not is_list(provider_plans) or provider_plans == []),
      issue("missing_provider_plans", ["phase2_evidence_plan", "provider_plans"], "Phase 2 evidence plan must include provider plans.")
    )
  end

  defp collect_results(errors, results, expected_commands) do
    cond do
      not is_list(results) or results == [] ->
        errors ++ [issue("required_field_missing", ["provider_preflight_results"], "Provider preflight results must be a non-empty array.")]

      true ->
        expected_by_key = Map.new(expected_commands, &{{Map.get(&1, "template"), Map.get(&1, "id")}, &1})

        errors ++
          result_errors(results, expected_by_key) ++
          result_coverage_errors(results, expected_by_key)
    end
  end

  defp result_errors(results, expected_by_key) do
    results
    |> Enum.with_index()
    |> Enum.flat_map(fn {result, index} -> result_errors(result, index, expected_by_key) end)
  end

  defp result_errors(result, index, expected_by_key) when is_map(result) do
    path = ["provider_preflight_results", index]
    template = value_at(result, ["template"])
    command_id = value_at(result, ["command_id"])
    expected = Map.get(expected_by_key, {template, command_id})
    status = value_at(result, ["status"])

    []
    |> collect_required_string_field(result, path ++ ["template"], "template")
    |> collect_required_string_field(result, path ++ ["command_id"], "command_id")
    |> maybe_add(
      non_empty_string?(template) and non_empty_string?(command_id) and is_nil(expected),
      issue("unknown_preflight_command", path, "Preflight result must match a planned read-only preflight command.")
    )
    |> collect_expected_value(result, expected, path, "target")
    |> collect_expected_value(result, expected, path, "provider_kind")
    |> collect_required_string_field(result, path ++ ["status"], "status")
    |> maybe_add(
      non_empty_string?(status) and status not in @statuses,
      issue("invalid_preflight_status", path ++ ["status"], "Preflight status must be passed or blocked.")
    )
    |> collect_required_string_field(result, path ++ ["ran_at"], "ran_at")
    |> collect_timestamp(result, path ++ ["ran_at"])
    |> maybe_add(
      value_at(result, ["side_effect_mode"]) != "read_only",
      issue("preflight_not_read_only", path ++ ["side_effect_mode"], "Preflight results must record read-only mode.")
    )
    |> maybe_add(
      value_at(result, ["write_performed"]) != false,
      issue("preflight_write_performed", path ++ ["write_performed"], "Preflight results must not record writes.")
    )
    |> maybe_add(
      value_at(result, ["production_enabled"]) != false,
      issue("preflight_enabled_production", path ++ ["production_enabled"], "Preflight results must not enable production.")
    )
    |> collect_blocker(result, expected, path)
    |> collect_raw_output_fields(result, path)
  end

  defp result_errors(_result, index, _expected_by_key) do
    [issue("invalid_type", ["provider_preflight_results", index], "Preflight result must be an object.")]
  end

  defp collect_expected_value(errors, _result, nil, _path, _field), do: errors

  defp collect_expected_value(errors, result, expected, path, field) do
    actual = value_at(result, [field])
    expected_value = Map.get(expected, field)

    errors
    |> collect_required_string_field(result, path ++ [field], field)
    |> maybe_add(
      non_empty_string?(actual) and actual != expected_value,
      issue("preflight_command_mismatch", path ++ [field], "Preflight result does not match the planned command.")
    )
  end

  defp collect_timestamp(errors, result, path) do
    timestamp = value_at(result, [List.last(path)])

    maybe_add(
      errors,
      non_empty_string?(timestamp) and not valid_datetime?(timestamp),
      issue("invalid_timestamp", path, "Preflight timestamp must be ISO8601.")
    )
  end

  defp collect_blocker(errors, result, expected, path) do
    status = value_at(result, ["status"])
    missing = value_at(result, ["missing_prerequisites"])

    cond do
      status == "blocked" ->
        errors
        |> collect_required_string_field(result, path ++ ["blocker_code"], "blocker_code")
        |> collect_string_list_field(result, path ++ ["missing_prerequisites"], "missing_prerequisites", "Blocked preflight results must list missing prerequisites.")
        |> collect_known_missing_prerequisites(missing, expected, path ++ ["missing_prerequisites"])

      status == "passed" ->
        maybe_add(
          errors,
          is_list(missing) and missing != [],
          issue("passed_preflight_has_missing_prerequisites", path ++ ["missing_prerequisites"], "Passed preflight results must not list missing prerequisites.")
        )

      true ->
        errors
    end
  end

  defp collect_known_missing_prerequisites(errors, missing, expected, path) when is_list(missing) and is_map(expected) do
    allowed = allowed_prerequisites(expected)

    missing
    |> Enum.reject(&(&1 in allowed))
    |> Enum.map(fn prerequisite ->
      issue("unknown_preflight_prerequisite", path, "Missing prerequisite must be declared by the planned preflight command.", %{prerequisite: prerequisite})
    end)
    |> then(&(errors ++ &1))
  end

  defp collect_known_missing_prerequisites(errors, _missing, _expected, _path), do: errors

  defp collect_raw_output_fields(errors, result, path) do
    @raw_output_fields
    |> Enum.filter(&Map.has_key?(result, &1))
    |> Enum.map(fn field ->
      issue("raw_preflight_output_forbidden", path ++ [field], "Preflight reports must not store raw output, environment, or token material.")
    end)
    |> then(&(errors ++ &1))
  end

  defp result_coverage_errors(results, expected_by_key) do
    observed =
      results
      |> Enum.filter(&is_map/1)
      |> Enum.map(&{value_at(&1, ["template"]), value_at(&1, ["command_id"])})
      |> Enum.filter(fn {template, command_id} -> non_empty_string?(template) and non_empty_string?(command_id) end)

    observed_counts = Enum.frequencies(observed)
    expected_keys = Map.keys(expected_by_key)
    observed_set = MapSet.new(observed)

    missing =
      expected_keys
      |> Enum.reject(&MapSet.member?(observed_set, &1))
      |> Enum.map(fn {template, command_id} ->
        issue("missing_preflight_result", ["provider_preflight_results"], "Every planned read-only preflight command must have one result.", %{
          template: template,
          command_id: command_id
        })
      end)

    duplicate =
      observed_counts
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {{template, command_id}, _count} ->
        issue("duplicate_preflight_result", ["provider_preflight_results"], "Preflight commands must not have duplicate results.", %{
          template: template,
          command_id: command_id
        })
      end)

    missing ++ duplicate
  end

  defp collect_explicit_non_claims(errors, packet) do
    non_claims = value_at(packet, ["explicit_non_claims"])

    errors
    |> collect_string_list(packet, ["explicit_non_claims"], "Explicit non-claims must be a non-empty string array.")
    |> maybe_add(
      is_list(non_claims) and "preflight_report_does_not_enable_production" not in non_claims,
      issue("missing_non_claim", ["explicit_non_claims"], "Preflight reports must state that production is not enabled.")
    )
  end

  defp normalize(packet, expected_commands) do
    results = Map.get(packet, "provider_preflight_results", [])
    status = if Enum.all?(results, &(Map.get(&1, "status") == "passed")), do: "passed", else: "blocked"

    packet
    |> Map.put("schema", @schema)
    |> Map.put("status", status)
    |> Map.put("planned_preflight_command_count", length(expected_commands))
    |> Map.put("preflight_result_count", length(results))
    |> Map.put("raw_output_included", false)
    |> Map.put("does_not_read_evidence_files", true)
    |> Map.put("does_not_call_providers", true)
    |> Map.put("does_not_mutate_workflow_state", true)
    |> Map.put("does_not_approve_production", true)
    |> Map.put("does_not_enable_production", true)
  end

  defp expected_commands(%{"provider_plans" => provider_plans}) when is_list(provider_plans) do
    Enum.flat_map(provider_plans, fn provider_plan ->
      template = Map.get(provider_plan, "template")
      entry_ids = Map.get(provider_plan, "provider_matrix_entry_ids", [])

      provider_plan
      |> value_at(["read_only_preflight", "commands"])
      |> case do
        commands when is_list(commands) ->
          Enum.map(commands, fn command ->
            command
            |> Map.put("template", template)
            |> Map.put("provider_matrix_entry_ids", entry_ids)
          end)

        _missing ->
          []
      end
    end)
  end

  defp expected_commands(_plan), do: []

  defp allowed_prerequisites(expected) do
    expected
    |> Map.take(["required_env", "required_auth", "required_targets"])
    |> Map.values()
    |> Enum.flat_map(fn
      values when is_list(values) -> values
      _value -> []
    end)
    |> Enum.uniq()
  end

  defp collect_required_map(errors, map, path) do
    value = value_at(map, path)

    maybe_add(errors, not is_map(value), issue("required_field_missing", path, "Required object field is missing."))
  end

  defp collect_required_string_field(errors, map, path, field) do
    value = value_at(map, [field])

    maybe_add(errors, not non_empty_string?(value), issue("required_field_missing", path, "Required string field is missing."))
  end

  defp collect_string_list(errors, map, path, message) do
    value = value_at(map, path)

    valid? = is_list(value) and value != [] and Enum.all?(value, &non_empty_string?/1)

    maybe_add(errors, not valid?, issue("invalid_string_list", path, message))
  end

  defp collect_string_list_field(errors, map, path, field, message) do
    value = value_at(map, [field])
    valid? = is_list(value) and value != [] and Enum.all?(value, &non_empty_string?/1)

    maybe_add(errors, not valid?, issue("invalid_string_list", path, message))
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery preflight report is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message, extra \\ %{}) do
    %{
      code: code,
      path: path,
      message: message
    }
    |> Map.merge(extra)
  end

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

  defp value_at(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, current ->
      if is_map(current) and Map.has_key?(current, key) do
        {:cont, Map.get(current, key)}
      else
        {:halt, nil}
      end
    end)
  end

  defp value_at(_map, _path), do: nil

  defp valid_datetime?(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> true
      {:error, _reason} -> false
    end
  end

  defp valid_datetime?(_value), do: false

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
end
