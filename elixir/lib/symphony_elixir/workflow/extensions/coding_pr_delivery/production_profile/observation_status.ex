defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatus do
  @moduledoc """
  Admission checks for post-apply observation-window status records.

  The status record proves that the approved observation window is being
  tracked after an external operator apply. It validates bounded observation
  metadata only; it does not inspect providers, mutate workflow state, apply
  settings, or enable production gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecord

  @schema "coding_pr_delivery.production_observation_status.v1"
  @error_code "coding_pr_delivery_observation_status_invalid"
  @statuses ["in_progress", "passed", "failed"]
  @criterion_statuses ["in_progress", "passed", "failed"]
  @placeholder_tokens ["fill-", "TODO", "REPLACE", "<", ">"]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate(map()) :: validation_result()
  def validate(status) when is_map(status) do
    record_result = status |> value_at(["operator_apply_record"]) |> OperatorApplyRecord.validate()
    apply_record = normalized_apply_record(record_result)

    errors =
      []
      |> collect_required_string(status, ["observation_status_id"])
      |> collect_required_string(status, ["observed_by"])
      |> collect_observed_at(status)
      |> collect_status(status)
      |> collect_nested_errors(record_result, ["operator_apply_record"])
      |> collect_observation_window(status, apply_record)
      |> collect_criteria(status, apply_record)
      |> collect_no_write_observation(status, apply_record)
      |> collect_status_consistency(status)

    if errors == [] do
      {:ok, normalize(status, apply_record)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate(_status) do
    {:error, invalid([issue("invalid_type", [], "Observation status must be an object.")])}
  end

  defp normalized_apply_record({:ok, record}), do: record
  defp normalized_apply_record(_result), do: %{}

  defp collect_observed_at(errors, status) do
    observed_at = value_at(status, ["observed_at"])

    errors
    |> collect_required_string(status, ["observed_at"])
    |> maybe_add(
      non_empty_string?(observed_at) and not valid_datetime?(observed_at),
      issue("invalid_timestamp", ["observed_at"], "Observed-at timestamp must be ISO8601.")
    )
  end

  defp collect_status(errors, status) do
    observed_status = value_at(status, ["status"])

    errors
    |> collect_required_string(status, ["status"])
    |> maybe_add(
      non_empty_string?(observed_status) and observed_status not in @statuses,
      issue("invalid_observation_status", ["status"], "Observation status is unsupported.", %{allowed_values: @statuses})
    )
  end

  defp collect_observation_window(errors, status, apply_record) do
    window = value_at(status, ["observation_window"])
    expected_window = value_at(apply_record, ["observation_start", "observation_window"])

    errors
    |> collect_required_map(status, ["observation_window"])
    |> maybe_add(
      is_map(window) and expected_window != nil and window != expected_window,
      issue("observation_window_mismatch", ["observation_window"], "Observation status window must match the approved apply record.")
    )
  end

  defp collect_criteria(errors, status, apply_record) do
    results = value_at(status, ["criteria_results"])
    expected = value_at(apply_record, ["observation_start", "observation_window", "success_criteria"])

    cond do
      not is_list(results) or results == [] ->
        errors ++ [issue("required_field_missing", ["criteria_results"], "Criteria results must be a non-empty array.")]

      true ->
        errors ++
          criteria_result_errors(results) ++
          criteria_coverage_errors(results, expected)
    end
  end

  defp criteria_result_errors(results) do
    results
    |> Enum.with_index()
    |> Enum.flat_map(fn {result, index} -> criteria_result_errors(result, index) end)
  end

  defp criteria_result_errors(result, index) when is_map(result) do
    path = ["criteria_results", index]
    observed_at = value_at(result, ["observed_at"])
    status = value_at(result, ["status"])

    []
    |> collect_required_string(result, path ++ ["criterion"])
    |> collect_required_string(result, path ++ ["status"])
    |> maybe_add(
      non_empty_string?(status) and status not in @criterion_statuses,
      issue("invalid_criterion_status", path ++ ["status"], "Criterion status is unsupported.", %{allowed_values: @criterion_statuses})
    )
    |> collect_required_string(result, path ++ ["observed_at"])
    |> maybe_add(
      non_empty_string?(observed_at) and not valid_datetime?(observed_at),
      issue("invalid_timestamp", path ++ ["observed_at"], "Criterion observed-at timestamp must be ISO8601.")
    )
    |> collect_string_list(result, path ++ ["evidence_files"], "Criterion evidence files must be a non-empty string array.")
    |> collect_evidence_files(result, path ++ ["evidence_files"])
  end

  defp criteria_result_errors(_result, index) do
    [issue("invalid_type", ["criteria_results", index], "Criteria result must be an object.")]
  end

  defp criteria_coverage_errors(results, expected) when is_list(expected) do
    observed =
      results
      |> Enum.filter(&is_map/1)
      |> Enum.map(&value_at(&1, ["criterion"]))
      |> Enum.filter(&non_empty_string?/1)

    observed_counts = Enum.frequencies(observed)

    missing =
      expected
      |> Enum.reject(&(&1 in observed))
      |> Enum.map(fn criterion ->
        issue("missing_criterion_result", ["criteria_results"], "Every observation success criterion must have one result.", %{criterion: criterion})
      end)

    duplicate =
      observed_counts
      |> Enum.filter(fn {_criterion, count} -> count > 1 end)
      |> Enum.map(fn {criterion, _count} ->
        issue("duplicate_criterion_result", ["criteria_results"], "Observation criterion must not be recorded more than once.", %{criterion: criterion})
      end)

    unexpected =
      observed
      |> Enum.reject(&(&1 in expected))
      |> Enum.uniq()
      |> Enum.map(fn criterion ->
        issue("unexpected_criterion_result", ["criteria_results"], "Observation criterion is outside the approved observation window.", %{criterion: criterion})
      end)

    missing ++ duplicate ++ unexpected
  end

  defp criteria_coverage_errors(_results, _expected), do: []

  defp collect_no_write_observation(errors, status, apply_record) do
    case value_at(apply_record, ["applied_scope", "side_effect_mode"]) do
      "shadow_no_write" ->
        no_write = value_at(status, ["no_write_observation"])

        errors
        |> collect_required_map(status, ["no_write_observation"])
        |> maybe_add(
          value_at(no_write, ["production_write_performed"]) != false,
          issue("shadow_production_write", ["no_write_observation", "production_write_performed"], "Shadow observation must not record production writes.")
        )
        |> maybe_add(
          value_at(no_write, ["canonical_surface_mutated"]) != false,
          issue("shadow_canonical_surface_mutated", ["no_write_observation", "canonical_surface_mutated"], "Shadow observation must not mutate canonical surfaces.")
        )

      _mode ->
        errors
    end
  end

  defp collect_status_consistency(errors, status) do
    observed_status = value_at(status, ["status"])
    criterion_statuses = criterion_statuses(status)

    cond do
      observed_status not in @statuses ->
        errors

      criterion_statuses == [] ->
        errors

      not Enum.all?(criterion_statuses, &(&1 in @criterion_statuses)) ->
        errors

      derived_status(criterion_statuses) != observed_status ->
        errors ++
          [
            issue("observation_status_mismatch", ["status"], "Observation status must match criterion results.", %{
              expected_status: derived_status(criterion_statuses)
            })
          ]

      true ->
        errors
    end
  end

  defp criterion_statuses(status) do
    status
    |> value_at(["criteria_results"])
    |> case do
      results when is_list(results) ->
        results
        |> Enum.filter(&is_map/1)
        |> Enum.map(&value_at(&1, ["status"]))
        |> Enum.filter(&non_empty_string?/1)

      _missing ->
        []
    end
  end

  defp derived_status(statuses) do
    cond do
      Enum.any?(statuses, &(&1 == "failed")) -> "failed"
      Enum.all?(statuses, &(&1 == "passed")) -> "passed"
      true -> "in_progress"
    end
  end

  defp normalize(status, apply_record) do
    %{
      "schema" => @schema,
      "observation_status_id" => value_at(status, ["observation_status_id"]),
      "status" => value_at(status, ["status"]),
      "profile_instance_id" => value_at(apply_record, ["profile_instance_id"]),
      "review_packet_id" => value_at(apply_record, ["review_packet_id"]),
      "enablement_request_id" => value_at(apply_record, ["enablement_request_id"]),
      "apply_record_id" => value_at(apply_record, ["apply_record_id"]),
      "observed_by" => value_at(status, ["observed_by"]),
      "observed_at" => value_at(status, ["observed_at"]),
      "observation_window" => value_at(status, ["observation_window"]),
      "criteria_results" => value_at(status, ["criteria_results"]),
      "no_write_observation" => value_at(status, ["no_write_observation"]),
      "records_observation_only" => true,
      "does_not_enable_production" => true
    }
  end

  defp collect_nested_errors(errors, {:ok, _value}, _path), do: errors

  defp collect_nested_errors(errors, {:error, %{errors: nested_errors}}, path) when is_list(nested_errors) do
    errors ++ Enum.map(nested_errors, &prefix_error(&1, path))
  end

  defp prefix_error(error, path) do
    %{
      code: error_code(error),
      path: path ++ error_path(error),
      message: error_message(error)
    }
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery observation status is invalid.",
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

  defp collect_evidence_files(errors, map, path) do
    evidence_files = value_at(map, [List.last(path)])

    if is_list(evidence_files) do
      evidence_files
      |> Enum.with_index()
      |> Enum.flat_map(fn {evidence_ref, index} -> evidence_ref_errors(evidence_ref, path ++ [index]) end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp evidence_ref_errors(evidence_ref, path) do
    []
    |> maybe_add(
      non_empty_string?(evidence_ref) and not allowed_evidence_ref?(evidence_ref),
      issue("invalid_evidence_ref", path, "Observation evidence references must be repository evidence paths or HTTP(S) links.")
    )
    |> maybe_add(
      non_empty_string?(evidence_ref) and placeholder_evidence_ref?(evidence_ref),
      issue("placeholder_evidence_ref", path, "Observation evidence references must not contain placeholders.")
    )
  end

  defp allowed_evidence_ref?(evidence_ref) do
    String.starts_with?(evidence_ref, "evidence/") or
      String.starts_with?(evidence_ref, "https://") or
      String.starts_with?(evidence_ref, "http://")
  end

  defp placeholder_evidence_ref?(evidence_ref) do
    downcased = String.downcase(evidence_ref)

    String.starts_with?(downcased, "/tmp/") or
      String.starts_with?(downcased, "tmp/") or
      String.starts_with?(downcased, "/var/") or
      String.starts_with?(downcased, "file://") or
      Enum.any?(@placeholder_tokens, &String.contains?(downcased, String.downcase(&1)))
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

  defp error_code(error), do: Map.get(error, :code) || Map.get(error, "code") || "invalid"
  defp error_path(error), do: Map.get(error, :path) || Map.get(error, "path") || []
  defp error_message(error), do: Map.get(error, :message) || Map.get(error, "message") || "Observation status is invalid."

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
