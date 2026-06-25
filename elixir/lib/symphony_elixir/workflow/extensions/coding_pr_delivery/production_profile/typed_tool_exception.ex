defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.TypedToolException do
  @moduledoc """
  Admission checks for scoped non-typed production tool exceptions.

  Production Coding PR Delivery defaults to typed tracker, repo-core, and
  repo-provider tools. This module validates exception evidence records before a
  production claim can cite them; it does not enable raw provider execution.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Contract, as: ProfileContract

  @error_code "coding_pr_delivery_typed_tool_exception_invalid"
  @broad_operation_tokens ["*", "all", "any", "raw_provider_passthrough", "provider_native_api", "provider_native_cli"]

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec validate_record(map()) :: validation_result()
  def validate_record(record) when is_map(record) do
    errors =
      []
      |> collect_required_string(record, ["exception_id"])
      |> collect_workflow_profile(record)
      |> collect_provider_kind(record, "tracker")
      |> collect_provider_kind(record, "repo_provider")
      |> collect_provider_kind(record, "agent_provider")
      |> collect_required_string(record, ["repository_class"])
      |> collect_required_string(record, ["workspace_class"])
      |> collect_route_set(record)
      |> collect_operation_set(record)
      |> collect_fallback_authority(record)
      |> collect_string_list(record, ["compensating_controls"], "Compensating controls must be a non-empty string array.")
      |> collect_input_schema_allowlist(record)
      |> collect_limits(record)
      |> collect_audit_logging(record)
      |> collect_string_list(record, ["deterministic_tests"], "Deterministic tests must be a non-empty string array.")
      |> collect_string_list(record, ["real_integration_evidence"], "Real integration evidence must be a non-empty string array.")
      |> collect_operator_observability(record)
      |> collect_rollback(record)
      |> collect_expiry_or_review(record)
      |> collect_forbidden_passthrough(record)

    if errors == [] do
      {:ok, normalize(record)}
    else
      {:error, invalid(errors)}
    end
  end

  def validate_record(_record) do
    {:error, invalid([issue("invalid_type", [], "Typed-tool production exception record must be an object.")])}
  end

  defp collect_workflow_profile(errors, record) do
    workflow_profile = value_at(record, ["workflow_profile"])

    errors
    |> collect_required_map(record, ["workflow_profile"])
    |> maybe_add(
      value_at(workflow_profile, ["kind"]) != ProfileContract.kind(),
      issue("invalid_workflow_profile", ["workflow_profile", "kind"], "Workflow profile kind must be coding_pr_delivery.")
    )
    |> maybe_add(
      value_at(workflow_profile, ["version"]) != ProfileContract.version(),
      issue("invalid_workflow_profile", ["workflow_profile", "version"], "Workflow profile version is unsupported.")
    )
  end

  defp collect_provider_kind(errors, record, provider_key) do
    errors
    |> collect_required_map(record, [provider_key])
    |> collect_required_string(record, [provider_key, "kind"])
  end

  defp collect_route_set(errors, record) do
    route_set = value_at(record, ["route_set"])
    allowed = allowed_route_keys()

    errors =
      maybe_add(
        errors,
        not string_list?(route_set) or route_set == [],
        issue("required_field_missing", ["route_set"], "Route set must be a non-empty string array.")
      )

    if is_list(route_set) do
      route_set
      |> Enum.reject(&(&1 in allowed))
      |> Enum.map(fn route -> issue("invalid_route_key", ["route_set", route], "Route key is outside the Coding PR Delivery profile.") end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp collect_operation_set(errors, record) do
    operation_set = value_at(record, ["operation_set"])

    errors =
      maybe_add(
        errors,
        not string_list?(operation_set) or operation_set == [],
        issue("required_field_missing", ["operation_set"], "Operation set must be a non-empty string array.")
      )

    if is_list(operation_set) do
      operation_set
      |> Enum.filter(&broad_operation?/1)
      |> Enum.map(fn operation ->
        issue("overbroad_operation_scope", ["operation_set", operation], "Exception operation set must not authorize broad raw provider passthrough.")
      end)
      |> then(&(errors ++ &1))
    else
      errors
    end
  end

  defp collect_fallback_authority(errors, record) do
    authority = value_at(record, ["fallback_authority"])

    errors
    |> collect_required_map(record, ["fallback_authority"])
    |> collect_required_string(record, ["fallback_authority", "owner"])
    |> collect_required_string(record, ["fallback_authority", "authority_kind"])
    |> maybe_add(
      value_at(authority, ["accepted_by_profile_owners"]) != true,
      issue("owner_approval_required", ["fallback_authority", "accepted_by_profile_owners"], "Fallback authority must be accepted by profile owners.")
    )
  end

  defp collect_input_schema_allowlist(errors, record) do
    allowlist = value_at(record, ["input_schema_allowlist"])

    errors
    |> collect_required_map(record, ["input_schema_allowlist"])
    |> collect_string_list(record, ["input_schema_allowlist", "schema_ids"], "Input schema allowlist must name at least one schema id.")
    |> maybe_add(
      value_at(allowlist, ["rejects_unknown_fields"]) != true,
      issue("strict_schema_required", ["input_schema_allowlist", "rejects_unknown_fields"], "Input schema allowlist must reject unknown fields.")
    )
  end

  defp collect_limits(errors, record) do
    errors
    |> collect_required_map(record, ["limits"])
    |> collect_positive_integer(record, ["limits", "max_calls_per_run"])
    |> collect_positive_integer(record, ["limits", "max_concurrency"])
  end

  defp collect_audit_logging(errors, record) do
    errors
    |> collect_required_map(record, ["audit_logging"])
    |> collect_required_string(record, ["audit_logging", "event_name"])
    |> collect_required_string(record, ["audit_logging", "retention_class"])
  end

  defp collect_operator_observability(errors, record) do
    errors
    |> collect_required_map(record, ["operator_observability"])
    |> collect_string_list(record, ["operator_observability", "metrics"], "Operator observability metrics must be a non-empty string array.")
    |> collect_string_list(record, ["operator_observability", "alerts"], "Operator observability alerts must be a non-empty string array.")
    |> collect_required_string(record, ["operator_observability", "runbook"])
  end

  defp collect_rollback(errors, record) do
    rollback = value_at(record, ["rollback"])

    errors
    |> collect_required_map(record, ["rollback"])
    |> collect_required_string(record, ["rollback", "owner"])
    |> collect_required_string(record, ["rollback", "instructions"])
    |> maybe_add(
      value_at(rollback, ["disables_exception"]) != true,
      issue("rollback_must_disable_exception", ["rollback", "disables_exception"], "Rollback must disable the production exception.")
    )
    |> maybe_add(
      value_at(rollback, ["restores_typed_tool_requirement"]) != true,
      issue("rollback_must_restore_typed_tools", ["rollback", "restores_typed_tool_requirement"], "Rollback must restore typed-tool requirements.")
    )
  end

  defp collect_expiry_or_review(errors, record) do
    expires_at = value_at(record, ["expires_at"])
    trigger = value_at(record, ["re_review_trigger"])

    cond do
      non_empty_string?(expires_at) and String.downcase(String.trim(expires_at)) != "never" ->
        errors

      is_map(trigger) ->
        errors
        |> collect_required_string(record, ["re_review_trigger", "condition"])
        |> collect_required_string(record, ["re_review_trigger", "owner"])

      true ->
        errors ++ [issue("expiry_or_re_review_required", [], "Exception record must include an expiry or re-review trigger.")]
    end
  end

  defp collect_forbidden_passthrough(errors, record) do
    errors
    |> maybe_add(
      value_at(record, ["raw_provider_passthrough"]) == true,
      issue("raw_provider_passthrough_forbidden", ["raw_provider_passthrough"], "Production exception must not authorize arbitrary raw provider passthrough.")
    )
    |> maybe_add(
      value_at(record, ["provider_native_prompt_snippets"]) == true,
      issue("provider_native_prompt_snippets_forbidden", ["provider_native_prompt_snippets"], "Production exception must not authorize provider-native API or CLI prompt snippets.")
    )
  end

  defp normalize(record) do
    %{
      "exception_id" => value_at(record, ["exception_id"]),
      "workflow_profile" => value_at(record, ["workflow_profile"]),
      "tracker" => %{"kind" => value_at(record, ["tracker", "kind"])},
      "repo_provider" => %{"kind" => value_at(record, ["repo_provider", "kind"])},
      "agent_provider" => %{"kind" => value_at(record, ["agent_provider", "kind"])},
      "repository_class" => value_at(record, ["repository_class"]),
      "workspace_class" => value_at(record, ["workspace_class"]),
      "route_set" => value_at(record, ["route_set"]),
      "operation_set" => value_at(record, ["operation_set"]),
      "fallback_authority" => value_at(record, ["fallback_authority"]),
      "compensating_controls" => value_at(record, ["compensating_controls"]),
      "input_schema_allowlist" => value_at(record, ["input_schema_allowlist"]),
      "limits" => value_at(record, ["limits"]),
      "audit_logging" => value_at(record, ["audit_logging"]),
      "deterministic_tests" => value_at(record, ["deterministic_tests"]),
      "real_integration_evidence" => value_at(record, ["real_integration_evidence"]),
      "operator_observability" => value_at(record, ["operator_observability"]),
      "rollback" => value_at(record, ["rollback"]),
      "expires_at" => value_at(record, ["expires_at"]),
      "re_review_trigger" => value_at(record, ["re_review_trigger"])
    }
  end

  defp collect_required_map(errors, map, path) do
    maybe_add(errors, not is_map(value_at(map, path)), issue("required_field_missing", path, "Field must be an object."))
  end

  defp collect_required_string(errors, map, path) do
    maybe_add(errors, not non_empty_string?(value_at(map, path)), issue("required_field_missing", path, "Field must be a non-empty string."))
  end

  defp collect_string_list(errors, map, path, message) do
    value = value_at(map, path)
    maybe_add(errors, not string_list?(value) or value == [], issue("required_field_missing", path, message))
  end

  defp collect_positive_integer(errors, map, path) do
    maybe_add(errors, not positive_integer?(value_at(map, path)), issue("required_field_missing", path, "Field must be a positive integer."))
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery typed-tool production exception is invalid.",
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

  defp allowed_route_keys, do: Enum.map(ProfileContract.route_keys(), &Atom.to_string/1)

  defp broad_operation?(operation) when is_binary(operation) do
    operation
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in @broad_operation_tokens))
  end

  defp broad_operation?(_operation), do: false

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp string_list?(values), do: is_list(values) and Enum.all?(values, &non_empty_string?/1)
end
