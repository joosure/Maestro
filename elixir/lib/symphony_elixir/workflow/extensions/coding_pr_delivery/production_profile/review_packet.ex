defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacket do
  @moduledoc """
  Admission checks for final Coding PR Delivery production review packets.

  This validator ties together the completed Phase 2 evidence packet with the
  Phase 4 review metadata required for a production decision. It validates
  packet structure only; it does not read evidence files, call providers, mutate
  workflow state, or enable production gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacket
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @schema "coding_pr_delivery.production_review_packet.v1"
  @error_code "coding_pr_delivery_review_packet_invalid"
  @operator_inspection_schema "workflow.execution_plan.operator_inspection.v1"
  @required_scrubbing_boundaries [
    "structured_plan_evidence_write",
    "structured_plan_render",
    "review_packet_render"
  ]
  @authority_boundary_flags [
    "prompt_wording_authoritative",
    "workpad_markdown_authoritative",
    "raw_provider_passthrough_authorized",
    "schema_support_alone_sufficient"
  ]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate(map()) :: validation_result()
  def validate(packet) when is_map(packet) do
    evidence_result = packet |> value_at(["evidence_packet"]) |> EvidencePacket.validate()

    errors =
      []
      |> collect_required_string(packet, ["review_packet_id"])
      |> collect_string_list(packet, ["changed_source_specs"], "Changed source specs must be a non-empty string array.")
      |> collect_string_list(packet, ["implementation_refs"], "Implementation refs must be a non-empty string array.")
      |> collect_deterministic_test_matrix(packet)
      |> collect_nested_errors(evidence_result, ["evidence_packet"])
      |> collect_rollback_instructions(packet)
      |> collect_scrubbing_pipeline(packet)
      |> collect_operator_inspection(packet)
      |> collect_retention_policy(packet)
      |> collect_authority_boundaries(packet)
      |> collect_owner_signoffs(packet)

    if errors == [] do
      {:ok, normalize(packet, evidence_result)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate(_packet) do
    {:error, invalid([issue("invalid_type", [], "Review packet must be an object.")])}
  end

  defp collect_deterministic_test_matrix(errors, packet) do
    matrix = value_at(packet, ["deterministic_test_matrix"])

    cond do
      not is_list(matrix) or matrix == [] ->
        errors ++ [issue("required_field_missing", ["deterministic_test_matrix"], "Deterministic test matrix must be a non-empty array.")]

      true ->
        errors ++
          (matrix
           |> Enum.with_index()
           |> Enum.flat_map(fn {entry, index} -> deterministic_test_entry_errors(entry, index) end))
    end
  end

  defp deterministic_test_entry_errors(entry, index) when is_map(entry) do
    path = ["deterministic_test_matrix", index]

    []
    |> collect_required_string(entry, path ++ ["command"])
    |> collect_required_string(entry, path ++ ["status"])
    |> maybe_add(
      value_at(entry, ["status"]) != "passed",
      issue("test_not_passed", path ++ ["status"], "Deterministic test matrix entries must be passed.")
    )
  end

  defp deterministic_test_entry_errors(_entry, index) do
    [issue("invalid_type", ["deterministic_test_matrix", index], "Deterministic test matrix entry must be an object.")]
  end

  defp collect_rollback_instructions(errors, packet) do
    rollback = value_at(packet, ["rollback_instructions"])

    errors
    |> collect_required_map(packet, ["rollback_instructions"])
    |> collect_required_string(rollback, ["rollback_instructions", "owner"])
    |> maybe_add(
      value_at(rollback, ["external_transition_readiness_gate"]) != Gates.transition_readiness_required_gate_key(),
      issue("invalid_transition_readiness_gate", ["rollback_instructions", "external_transition_readiness_gate"], "Rollback instructions must use the external transition readiness gate key.")
    )
    |> maybe_add(
      value_at(rollback, ["legacy_review_handoff_required_mapping"]) != true,
      issue(
        "missing_legacy_gate_mapping",
        ["rollback_instructions", "legacy_review_handoff_required_mapping"],
        "Rollback instructions must record the review_handoff_required to external gate mapping."
      )
    )
    |> collect_string_list(rollback, ["rollback_instructions", "disable_gates"], "Rollback disable gates must be a non-empty string array.")
    |> collect_required_gate(rollback, ["rollback_instructions", "disable_gates"], Gates.transition_readiness_required_gate_key())
  end

  defp collect_scrubbing_pipeline(errors, packet) do
    scrubbing = value_at(packet, ["scrubbing_pipeline"])

    errors
    |> collect_required_map(packet, ["scrubbing_pipeline"])
    |> collect_required_string(scrubbing, ["scrubbing_pipeline", "owner"])
    |> collect_required_string(scrubbing, ["scrubbing_pipeline", "pattern_catalog_version"])
    |> maybe_add(
      value_at(scrubbing, ["failure_behavior"]) != "fail_closed",
      issue("scrubbing_not_fail_closed", ["scrubbing_pipeline", "failure_behavior"], "Scrubbing pipeline must fail closed.")
    )
    |> collect_string_list(scrubbing, ["scrubbing_pipeline", "enforced_boundaries"], "Scrubbing enforced boundaries must be a non-empty string array.")
    |> collect_required_boundaries(scrubbing)
    |> collect_test_results(scrubbing, ["scrubbing_pipeline", "test_results"])
  end

  defp collect_required_boundaries(errors, scrubbing) do
    boundaries = value_at(scrubbing, ["enforced_boundaries"])

    if is_list(boundaries) do
      @required_scrubbing_boundaries
      |> Enum.reject(&(&1 in boundaries))
      |> Enum.map(fn boundary ->
        issue("missing_scrubbing_boundary", ["scrubbing_pipeline", "enforced_boundaries"], "Required scrubbing boundary is missing.", %{boundary: boundary})
      end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp collect_operator_inspection(errors, packet) do
    inspection = value_at(packet, ["operator_inspection"])
    gate_values = value_at(inspection, ["gate_values"])

    errors
    |> collect_required_map(packet, ["operator_inspection"])
    |> maybe_add(
      value_at(inspection, ["schema"]) != @operator_inspection_schema,
      issue("invalid_operator_inspection_schema", ["operator_inspection", "schema"], "Operator inspection packet schema is invalid.")
    )
    |> maybe_add(
      not is_map(gate_values),
      issue("required_field_missing", ["operator_inspection", "gate_values"], "Operator inspection gate values must be an object.")
    )
    |> maybe_add(
      is_map(gate_values) and Map.has_key?(gate_values, "review_handoff_required"),
      issue("legacy_gate_name", ["operator_inspection", "gate_values", "review_handoff_required"], "Legacy review_handoff_required gate must not appear in production review packets.")
    )
    |> maybe_add(
      is_map(gate_values) and not Map.has_key?(gate_values, Gates.transition_readiness_required_gate_key()),
      issue("missing_transition_readiness_gate", ["operator_inspection", "gate_values"], "Operator inspection must include the external transition readiness gate.")
    )
    |> maybe_add(
      value_at(inspection, ["contains_raw_evidence_payload"]) != false,
      issue("raw_evidence_payload_present", ["operator_inspection", "contains_raw_evidence_payload"], "Operator inspection must not include raw evidence payloads.")
    )
    |> maybe_add(
      value_at(inspection, ["workpad_markdown_authoritative"]) != false,
      issue("workpad_authority", ["operator_inspection", "workpad_markdown_authoritative"], "Workpad Markdown must not be authoritative.")
    )
  end

  defp collect_retention_policy(errors, packet) do
    retention = value_at(packet, ["retention_policy"])
    days = value_at(retention, ["retention_period_days"])

    errors
    |> collect_required_map(packet, ["retention_policy"])
    |> collect_required_string(retention, ["retention_policy", "retention_class"])
    |> collect_required_string(retention, ["retention_policy", "cleanup_owner"])
    |> maybe_add(
      not is_integer(days) or days <= 0,
      issue("invalid_retention_period", ["retention_policy", "retention_period_days"], "Retention period must be a positive integer.")
    )
    |> maybe_add(
      value_at(retention, ["tombstone_preserving"]) != true,
      issue("retention_without_tombstones", ["retention_policy", "tombstone_preserving"], "Retention policy must preserve tombstones.")
    )
  end

  defp collect_authority_boundaries(errors, packet) do
    boundaries = value_at(packet, ["authority_boundaries"])

    errors =
      collect_required_map(errors, packet, ["authority_boundaries"])

    if is_map(boundaries) do
      @authority_boundary_flags
      |> Enum.filter(&(value_at(boundaries, [&1]) != false))
      |> Enum.map(fn flag ->
        issue("invalid_authority_boundary", ["authority_boundaries", flag], "Production review packet must explicitly reject non-canonical authority.", %{flag: flag})
      end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp collect_owner_signoffs(errors, packet) do
    signoffs = value_at(packet, ["owner_signoffs"])

    cond do
      not is_list(signoffs) or signoffs == [] ->
        errors ++ [issue("required_field_missing", ["owner_signoffs"], "Owner sign-offs must be a non-empty array.")]

      true ->
        errors ++
          (signoffs
           |> Enum.with_index()
           |> Enum.flat_map(fn {signoff, index} -> signoff_errors(signoff, index) end))
    end
  end

  defp signoff_errors(signoff, index) when is_map(signoff) do
    path = ["owner_signoffs", index]
    approved_at = value_at(signoff, ["approved_at"])

    []
    |> collect_required_string(signoff, path ++ ["role"])
    |> collect_required_string(signoff, path ++ ["owner"])
    |> collect_required_string(signoff, path ++ ["approved_at"])
    |> maybe_add(
      non_empty_string?(approved_at) and not valid_datetime?(approved_at),
      issue("invalid_timestamp", path ++ ["approved_at"], "Approved-at timestamp must be ISO8601.")
    )
    |> maybe_add(
      value_at(signoff, ["decision"]) != "approved",
      issue("signoff_not_approved", path ++ ["decision"], "Owner sign-off decision must be approved.")
    )
  end

  defp signoff_errors(_signoff, index) do
    [issue("invalid_type", ["owner_signoffs", index], "Owner sign-off must be an object.")]
  end

  defp collect_test_results(errors, map, path) do
    results = value_at(map, [List.last(path)])

    cond do
      not is_list(results) or results == [] ->
        errors ++ [issue("required_field_missing", path, "Test results must be a non-empty array.")]

      true ->
        errors ++
          (results
           |> Enum.with_index()
           |> Enum.flat_map(fn {result, index} -> test_result_errors(result, path, index) end))
    end
  end

  defp test_result_errors(result, path, index) when is_map(result) do
    result_path = path ++ [index]

    []
    |> collect_required_string(result, result_path ++ ["name"])
    |> collect_required_string(result, result_path ++ ["status"])
    |> maybe_add(
      value_at(result, ["status"]) != "passed",
      issue("test_not_passed", result_path ++ ["status"], "Test result must be passed.")
    )
  end

  defp test_result_errors(_result, path, index) do
    [issue("invalid_type", path ++ [index], "Test result must be an object.")]
  end

  defp collect_required_gate(errors, map, path, gate_key) do
    gates = value_at(map, [List.last(path)])

    if is_list(gates) and gate_key not in gates do
      errors ++ [issue("missing_rollback_gate", path, "Rollback instructions must disable the transition readiness gate.", %{gate: gate_key})]
    else
      errors
    end
  end

  defp normalize(packet, {:ok, evidence_packet}) do
    %{
      "schema" => @schema,
      "review_packet_id" => value_at(packet, ["review_packet_id"]),
      "profile_instance_id" => Map.get(evidence_packet, "profile_instance_id"),
      "evidence_packet" => evidence_packet,
      "changed_source_specs" => value_at(packet, ["changed_source_specs"]),
      "implementation_refs" => value_at(packet, ["implementation_refs"]),
      "deterministic_test_matrix" => value_at(packet, ["deterministic_test_matrix"]),
      "rollback_instructions" => value_at(packet, ["rollback_instructions"]),
      "scrubbing_pipeline" => value_at(packet, ["scrubbing_pipeline"]),
      "operator_inspection" => value_at(packet, ["operator_inspection"]),
      "retention_policy" => value_at(packet, ["retention_policy"]),
      "authority_boundaries" => value_at(packet, ["authority_boundaries"]),
      "owner_signoffs" => value_at(packet, ["owner_signoffs"])
    }
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery review packet is invalid.",
      errors: errors
    }
  end

  defp collect_nested_errors(errors, {:ok, _value}, _path), do: errors

  defp collect_nested_errors(errors, {:error, %{errors: nested_errors}}, path) when is_list(nested_errors) do
    errors ++ Enum.map(nested_errors, &prefix_error(&1, path))
  end

  defp collect_nested_errors(errors, {:error, reason}, path) do
    errors ++ [issue(error_code(reason), path, error_message(reason))]
  end

  defp prefix_error(error, path) do
    %{
      code: error_code(error),
      path: path ++ error_path(error),
      message: error_message(error)
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

  defp error_code(error), do: Map.get(error, :code) || Map.get(error, "code") || "invalid"
  defp error_path(error), do: Map.get(error, :path) || Map.get(error, "path") || []
  defp error_message(error), do: Map.get(error, :message) || Map.get(error, "message") || "Invalid review packet."

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
