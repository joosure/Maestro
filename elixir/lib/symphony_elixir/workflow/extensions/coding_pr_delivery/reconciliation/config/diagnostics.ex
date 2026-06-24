defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Diagnostics do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics, as: ExtensionDiagnostics
  alias SymphonyElixir.Workflow.RouteRef

  @spec format(term()) :: String.t()
  def format({:unsupported_field, field_path}) do
    "unsupported_field path=#{field_name(field_path)}"
  end

  def format({:invalid_section, section, value}) when is_binary(section) do
    "invalid_section section=#{section} value_type=#{ExtensionDiagnostics.type_name(value)}"
  end

  def format({:invalid_route_key, field_path, reason}) do
    "invalid_route_key path=#{field_name(field_path)} #{route_reason(reason)}"
    |> String.trim()
  end

  def format({:invalid_route_list, field_path, value}) do
    "invalid_route_list path=#{field_name(field_path)} value_type=#{ExtensionDiagnostics.type_name(value)}"
  end

  def format({:invalid_candidate_discovery, field_path, value, allowed_modes}) do
    "invalid_candidate_discovery path=#{field_name(field_path)} value_type=#{ExtensionDiagnostics.type_name(value)} allowed=#{token_list(allowed_modes)}"
  end

  def format({:invalid_boolean, field_path, value}) do
    "invalid_boolean path=#{field_name(field_path)} value_type=#{ExtensionDiagnostics.type_name(value)}"
  end

  def format({:invalid_positive_integer, field_path, value}) do
    "invalid_positive_integer path=#{field_name(field_path)} value_type=#{ExtensionDiagnostics.type_name(value)}"
  end

  def format({:max_processed_issues_per_cycle_too_large, field_path, value, limit}) do
    "max_processed_issues_per_cycle_too_large path=#{field_name(field_path)} value=#{token(value)} limit=#{token(limit)}"
  end

  def format({:invalid_target_route_lifecycle_phase, field_path, route_ref, phase, expected_phase}) do
    "invalid_target_route_lifecycle_phase path=#{field_name(field_path)} route=#{route_name(route_ref)} phase=#{token(phase)} expected_phase=#{token(expected_phase)}"
  end

  def format({:invalid_target_route_policy_action, field_path, route_ref, action, expected_actions}) do
    "invalid_target_route_policy_action path=#{field_name(field_path)} route=#{route_name(route_ref)} action=#{token(action)} expected_actions=#{token_list(expected_actions)}"
  end

  def format(reason) when is_atom(reason), do: Atom.to_string(reason)

  def format(reason) do
    "invalid_config reason_type=#{ExtensionDiagnostics.type_name(reason)}"
  end

  @spec field_name(term()) :: String.t()
  def field_name(field) when is_binary(field), do: field
  def field_name(field) when is_atom(field), do: Atom.to_string(field)
  def field_name(%RouteRef{}), do: "route_ref"

  def field_name(field) do
    "field_type=#{ExtensionDiagnostics.type_name(field)}"
  end

  defp route_reason({:invalid_workflow_route_key, profile_kind, profile_version, route_key}) do
    "reason=invalid_workflow_route_key profile=#{token(profile_kind)} version=#{token(profile_version)} route=#{token(route_key)}"
  end

  defp route_reason(reason), do: "reason_type=#{ExtensionDiagnostics.type_name(reason)}"

  defp route_name(%RouteRef{route_key: route_key}), do: token(route_key)
  defp route_name(route), do: "route_type=#{ExtensionDiagnostics.type_name(route)}"

  defp token(value) when is_binary(value), do: value
  defp token(value) when is_atom(value), do: Atom.to_string(value)
  defp token(value) when is_integer(value), do: Integer.to_string(value)
  defp token(nil), do: "nil"
  defp token(value), do: "value_type=#{ExtensionDiagnostics.type_name(value)}"

  defp token_list(values) when is_list(values), do: Enum.map_join(values, ",", &token/1)
  defp token_list(value), do: "value_type=#{ExtensionDiagnostics.type_name(value)}"
end
