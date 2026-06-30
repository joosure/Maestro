defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance do
  @moduledoc """
  Production governance evidence checks for structured execution plans.

  This module validates the retention, tombstone, cleanup, and rollback portions
  of a production enablement packet. It is intentionally pure: it does not prune,
  redact, delete, or mutate stored plan records.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract

  @schema "workflow.execution_plan.production_governance.v1"
  @error_code "structured_execution_plan_production_governance_invalid"
  @required_tombstone_fields [
    "plan_id",
    "run_id",
    "issue_id",
    "workflow_profile",
    "route_key",
    "retention_class",
    "tombstoned_at",
    "tombstoned_by",
    "tombstone_reason"
  ]
  @required_scrubbing_pattern_rules [
    "api_keys",
    "bearer_tokens",
    "jwt",
    "passwords",
    "private_keys",
    "connection_strings",
    "cloud_credentials",
    "provider_auth_material"
  ]
  @placeholder_tokens ["fill-", "TODO", "REPLACE", "<", ">"]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec required_tombstone_fields() :: [String.t()]
  def required_tombstone_fields, do: @required_tombstone_fields

  @spec required_scrubbing_pattern_rules() :: [String.t()]
  def required_scrubbing_pattern_rules, do: @required_scrubbing_pattern_rules

  @spec validate_packet(map()) :: validation_result()
  def validate_packet(packet) when is_map(packet) do
    errors =
      []
      |> collect_required_string(packet, ["profile_instance_id"])
      |> collect_durability_profile(packet)
      |> collect_data_governance(packet)
      |> collect_rollback(packet)
      |> collect_string_list(packet, ["evidence_files"], "Evidence files must be a non-empty string array.")
      |> collect_evidence_refs(packet, ["evidence_files"])

    if errors == [] do
      {:ok, normalize_packet(packet)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate_packet(_packet) do
    {:error, invalid([issue("invalid_type", [], "Production governance packet must be an object.")])}
  end

  defp collect_durability_profile(errors, packet) do
    profile = value_at(packet, ["durability_profile"])

    errors
    |> collect_required_map(packet, ["durability_profile"])
    |> collect_required_string(packet, ["durability_profile", "storage_backend"])
    |> collect_required_string(packet, ["durability_profile", "restart_behavior"])
    |> collect_required_string(packet, ["durability_profile", "backup_restore"])
    |> collect_required_string(packet, ["durability_profile", "retention_class"])
    |> collect_positive_integer(packet, ["durability_profile", "retention_period_days"])
    |> collect_required_string(packet, ["durability_profile", "cleanup_behavior"])
    |> collect_required_boolean(profile, ["durability_profile", "survives_process_restart"])
    |> collect_required_boolean(profile, ["durability_profile", "survives_worker_restart"])
    |> collect_required_boolean(profile, ["durability_profile", "survives_service_restart"])
  end

  defp collect_data_governance(errors, packet) do
    data_governance = value_at(packet, ["data_governance"])

    errors
    |> collect_required_map(packet, ["data_governance"])
    |> collect_required_string(packet, ["data_governance", "data_classification"])
    |> collect_required_string(packet, ["data_governance", "redaction_policy"])
    |> collect_required_string(packet, ["data_governance", "retention_class"])
    |> collect_positive_integer(packet, ["data_governance", "retention_period_days"])
    |> collect_required_string(packet, ["data_governance", "cleanup_owner"])
    |> collect_required_string(packet, ["data_governance", "cleanup_schedule"])
    |> collect_scrubbing_pipeline(data_governance)
    |> collect_tombstone(data_governance)
  end

  defp collect_scrubbing_pipeline(errors, data_governance) do
    pipeline = value_at(data_governance, ["scrubbing_pipeline"])

    errors
    |> collect_required_map(data_governance, ["scrubbing_pipeline"])
    |> collect_required_string(data_governance, ["scrubbing_pipeline", "owner"])
    |> collect_required_string(data_governance, ["scrubbing_pipeline", "pattern_catalog_version"])
    |> collect_string_list(data_governance, ["scrubbing_pipeline", "pattern_catalog_rules"], "Scrubbing pattern catalog rules must be a non-empty string array.")
    |> collect_required_scrubbing_rules(pipeline)
    |> collect_string_list(data_governance, ["scrubbing_pipeline", "enforced_boundaries"], "Scrubbing enforced boundaries must be a non-empty string array.")
    |> maybe_add(
      value_at(pipeline, ["failure_behavior"]) != "fail_closed",
      issue("invalid_scrubbing_failure_behavior", ["data_governance", "scrubbing_pipeline", "failure_behavior"], "Scrubbing failure behavior must fail closed.")
    )
  end

  defp collect_required_scrubbing_rules(errors, pipeline) do
    rules = value_at(pipeline, ["pattern_catalog_rules"])

    if is_list(rules) do
      @required_scrubbing_pattern_rules
      |> Enum.reject(&(&1 in rules))
      |> Enum.map(fn rule ->
        issue("missing_scrubbing_pattern_rule", ["data_governance", "scrubbing_pipeline", "pattern_catalog_rules", rule], "Required scrubbing pattern rule is missing.")
      end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp collect_tombstone(errors, data_governance) do
    tombstone = value_at(data_governance, ["tombstone"])
    fields = value_at(tombstone, ["metadata_fields"])

    errors
    |> collect_required_map(data_governance, ["tombstone"])
    |> maybe_add(
      not string_list?(fields) or fields == [],
      issue("required_field_missing", ["data_governance", "tombstone", "metadata_fields"], "Tombstone metadata fields must be a non-empty string array.")
    )
    |> collect_required_tombstone_fields(fields)
    |> collect_true(tombstone, ["prevents_id_reuse"], ["data_governance", "tombstone", "prevents_id_reuse"], "Tombstones must prevent plan id reuse.")
    |> collect_true(
      tombstone,
      ["prevents_hidden_readiness_claims"],
      ["data_governance", "tombstone", "prevents_hidden_readiness_claims"],
      "Tombstones must prevent hidden readiness claims."
    )
    |> collect_true(tombstone, ["preserves_audit_trail"], ["data_governance", "tombstone", "preserves_audit_trail"], "Tombstones must preserve audit trail context.")
  end

  defp collect_required_tombstone_fields(errors, fields) when is_list(fields) do
    missing =
      @required_tombstone_fields
      |> Enum.reject(&(&1 in fields))
      |> Enum.map(fn field ->
        issue("missing_tombstone_metadata", ["data_governance", "tombstone", "metadata_fields", field], "Required tombstone metadata field is missing.")
      end)

    errors ++ missing
  end

  defp collect_required_tombstone_fields(errors, _fields), do: errors

  defp collect_rollback(errors, packet) do
    rollback = value_at(packet, ["rollback"])

    errors
    |> collect_required_map(packet, ["rollback"])
    |> collect_true(
      rollback,
      ["preserves_stored_plans_and_evidence"],
      ["rollback", "preserves_stored_plans_and_evidence"],
      "Rollback must preserve stored plans and evidence."
    )
    |> collect_false(rollback, ["deletes_records"], ["rollback", "deletes_records"], "Rollback must not delete plan, evidence, or audit records.")
    |> collect_false(rollback, ["rewrites_evidence"], ["rollback", "rewrites_evidence"], "Rollback must not rewrite evidence.")
    |> collect_false(
      rollback,
      ["makes_workpad_authoritative"],
      ["rollback", "makes_workpad_authoritative"],
      "Rollback must not make Workpad Markdown authoritative."
    )
    |> collect_rollback_gate(rollback, "disable_recording_gate", Contract.enabled_gate_key())
    |> collect_rollback_gate(rollback, "disable_rendering_gate", Contract.render_workpad_gate_key())
    |> collect_rollback_gate(rollback, "disable_readiness_gate", Contract.transition_readiness_required_gate_key())
    |> collect_rollback_gate(rollback, "disable_provider_adapters_gate", Contract.provider_adapters_enabled_gate_key())
  end

  defp collect_rollback_gate(errors, rollback, key, expected) do
    maybe_add(
      errors,
      value_at(rollback, [key]) != expected,
      issue("invalid_rollback_gate", ["rollback", key], "Rollback gate must use the canonical external gate key.")
    )
  end

  defp normalize_packet(packet) do
    %{
      "schema" => @schema,
      "profile_instance_id" => value_at(packet, ["profile_instance_id"]),
      "durability_profile" => value_at(packet, ["durability_profile"]),
      "data_governance" => value_at(packet, ["data_governance"]),
      "rollback" => value_at(packet, ["rollback"]),
      "evidence_files" => value_at(packet, ["evidence_files"])
    }
  end

  defp collect_required_map(errors, map, path) do
    maybe_add(errors, not is_map(value_at(map, path)), issue("required_field_missing", path, "Field must be an object."))
  end

  defp collect_required_string(errors, map, path) do
    maybe_add(errors, not non_empty_string?(value_at(map, path)), issue("required_field_missing", path, "Field must be a non-empty string."))
  end

  defp collect_positive_integer(errors, map, path) do
    maybe_add(errors, not positive_integer?(value_at(map, path)), issue("required_field_missing", path, "Field must be a positive integer."))
  end

  defp collect_required_boolean(errors, map, path) do
    maybe_add(errors, not is_boolean(value_at(map, path_from_root(path))), issue("required_field_missing", path, "Field must be a boolean."))
  end

  defp collect_string_list(errors, map, path, message) do
    value = value_at(map, path)
    maybe_add(errors, not string_list?(value) or value == [], issue("required_field_missing", path, message))
  end

  defp collect_evidence_refs(errors, map, path) do
    refs = value_at(map, path)

    if is_list(refs) do
      refs
      |> Enum.with_index()
      |> Enum.flat_map(fn {ref, index} -> evidence_ref_errors(ref, path ++ [index]) end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp evidence_ref_errors(ref, path) do
    []
    |> maybe_add(
      non_empty_string?(ref) and not allowed_evidence_ref?(ref),
      issue("invalid_evidence_ref", path, "Evidence references must be repository evidence paths or HTTP(S) links.")
    )
    |> maybe_add(
      non_empty_string?(ref) and placeholder_evidence_ref?(ref),
      issue("placeholder_evidence_ref", path, "Evidence references must not contain placeholders.")
    )
  end

  defp allowed_evidence_ref?(ref) do
    String.starts_with?(ref, "evidence/") or
      String.starts_with?(ref, "https://") or
      String.starts_with?(ref, "http://")
  end

  defp placeholder_evidence_ref?(ref) do
    downcased = String.downcase(ref)

    String.starts_with?(downcased, "/tmp/") or
      String.starts_with?(downcased, "tmp/") or
      String.starts_with?(downcased, "/var/") or
      String.starts_with?(downcased, "file://") or
      Enum.any?(@placeholder_tokens, &String.contains?(downcased, String.downcase(&1)))
  end

  defp collect_true(errors, map, value_path, error_path, message) do
    maybe_add(errors, value_at(map, value_path) != true, issue("required_field_missing", error_path, message))
  end

  defp collect_false(errors, map, value_path, error_path, message) do
    maybe_add(errors, value_at(map, value_path) != false, issue("invalid_destructive_rollback", error_path, message))
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Structured execution plan production governance packet is invalid.",
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

  defp path_from_root([_root | rest]), do: rest

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp string_list?(values), do: is_list(values) and Enum.all?(values, &non_empty_string?/1)
end
