defmodule SymphonyElixir.Workflow.StateTransitionReadiness.DynamicToolFailureDiagnostics do
  @moduledoc """
  Extracts compact readiness diagnostics from Dynamic Tool failure envelopes.

  Dynamic tools keep their full failure payload in `result_summary`. This module
  exposes only stable workflow-readiness fields for logs and metrics.
  """

  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @payload_key Response.payload_key()
  @error_key Response.error_key()
  @code_key Response.code_key()
  @details_key "details"
  @original_code_key "original_code"
  @checks_key "checks"
  @key_key "key"
  @reason_code_key "reason_code"
  @reason_codes_key "reason_codes"
  @status_key "status"
  @target_state_key "target_state"
  @missing_evidence_key "missing_evidence"
  @remediation_actions_key "remediation_actions"
  @action_key "action"
  @capabilities_key "capabilities"
  @check_key "check"
  @not_ready_suffix "_not_ready"
  @passing_check_statuses MapSet.new(["passed", "not_required"])

  @spec fields(term()) :: map()
  def fields(result) do
    with payload when is_map(payload) <- field_value(result, @payload_key),
         error when is_map(error) <- field_value(payload, @error_key),
         details when is_map(details) <- field_value(error, @details_key),
         true <- readiness_details?(error, details) do
      checks = list_field(details, @checks_key)
      failed_check_keys = failed_check_keys(checks)
      reason_codes = reason_codes(details, checks)

      %{
        readiness_error_code: readiness_error_code(error, details),
        readiness_reason_codes: reason_codes,
        readiness_failed_check_keys: failed_check_keys,
        readiness_failed_check_count: length(failed_check_keys),
        readiness_remediation_actions: remediation_actions(details),
        readiness_target_state: string_field(details, @target_state_key)
      }
      |> drop_empty_values()
    else
      _value -> %{}
    end
  end

  defp readiness_details?(error, details) do
    error
    |> readiness_error_code(details)
    |> not_ready_code?() or
      non_empty_list_field?(details, @reason_codes_key)
  end

  defp readiness_error_code(error, details) do
    string_field(details, @original_code_key) || string_field(error, @code_key)
  end

  defp not_ready_code?(code) when is_binary(code), do: String.ends_with?(code, @not_ready_suffix)
  defp not_ready_code?(_code), do: false

  defp reason_codes(details, checks) do
    details
    |> list_field(@reason_codes_key)
    |> normalize_strings()
    |> fallback(fn -> checks |> failed_check_reason_codes() |> normalize_strings() end)
    |> fallback(fn -> details |> missing_evidence_reason_codes() |> normalize_strings() end)
  end

  defp failed_check_keys(checks) do
    checks
    |> Enum.filter(&failed_check?/1)
    |> Enum.map(&string_field(&1, @key_key))
    |> normalize_strings()
  end

  defp failed_check_reason_codes(checks) do
    checks
    |> Enum.filter(&failed_check?/1)
    |> Enum.map(&string_field(&1, @reason_code_key))
  end

  defp failed_check?(check) when is_map(check) do
    status = string_field(check, @status_key)
    not MapSet.member?(@passing_check_statuses, status)
  end

  defp failed_check?(_check), do: false

  defp missing_evidence_reason_codes(details) do
    details
    |> list_field(@missing_evidence_key)
    |> Enum.map(&string_field(&1, @code_key))
  end

  defp remediation_actions(details) do
    details
    |> list_field(@remediation_actions_key)
    |> Enum.filter(&is_map/1)
    |> Enum.map(&remediation_action/1)
    |> Enum.reject(&(&1 == %{}))
  end

  defp remediation_action(action) do
    %{
      @reason_code_key => string_field(action, @reason_code_key),
      @check_key => string_field(action, @check_key),
      @action_key => string_field(action, @action_key),
      @capabilities_key => action |> list_field(@capabilities_key) |> normalize_strings()
    }
    |> drop_empty_values()
  end

  defp field_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key)
  end

  defp field_value(_value, _key), do: nil

  defp string_field(map, key) do
    case field_value(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _value ->
        nil
    end
  end

  defp list_field(map, key) do
    case field_value(map, key) do
      values when is_list(values) -> values
      _value -> []
    end
  end

  defp non_empty_list_field?(map, key), do: map |> list_field(key) |> Enum.any?()

  defp normalize_strings(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp fallback([], fun) when is_function(fun, 0), do: fun.()
  defp fallback(values, _fun), do: values

  defp drop_empty_values(map) do
    Map.reject(map, fn
      {_key, nil} -> true
      {_key, []} -> true
      {_key, 0} -> true
      {_key, _value} -> false
    end)
  end
end
