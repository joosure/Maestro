defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition.Diagnostics do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics, as: ExtensionDiagnostics
  alias SymphonyElixir.Workflow.RouteRef

  @spec invalid_options(term()) :: map()
  def invalid_options(opts), do: %{reason: :invalid_options, value_type: ExtensionDiagnostics.detailed_type_atom(opts)}

  @spec invalid_dependency(atom(), term(), non_neg_integer()) :: map()
  def invalid_dependency(name, value, arity) when is_atom(name) do
    %{
      reason: :invalid_dependency,
      dependency: Atom.to_string(name),
      expected_arity: arity,
      value_type: ExtensionDiagnostics.detailed_type_atom(value)
    }
  end

  @spec invalid_dry_run(term()) :: map()
  def invalid_dry_run(value), do: %{reason: :invalid_dry_run, value_type: ExtensionDiagnostics.detailed_type_atom(value)}

  @spec invalid_result(atom(), term()) :: map()
  def invalid_result(operation, value) when is_atom(operation) do
    %{
      reason: :invalid_result,
      operation: operation,
      value_type: ExtensionDiagnostics.detailed_type_atom(value)
    }
  end

  @spec callback_failed(atom(), term(), term()) :: map()
  def callback_failed(operation, kind, reason) when is_atom(operation) do
    %{
      reason: :callback_failed,
      operation: operation,
      kind: kind,
      reason_type: ExtensionDiagnostics.detailed_type_atom(reason)
    }
  end

  @spec callback_exception(atom(), Exception.t()) :: map()
  def callback_exception(operation, error) when is_atom(operation) do
    %{
      reason: :callback_failed,
      operation: operation,
      exception: inspect(error.__struct__)
    }
  end

  @spec missing_raw_state_for_route_key(RouteRef.t() | term()) :: map()
  def missing_raw_state_for_route_key(%RouteRef{} = route_ref) do
    %{
      reason: :missing_raw_state_for_route_key,
      target_route_key: route_key_name(route_ref.route_key),
      target_workflow_profile: route_ref.profile_kind,
      target_workflow_profile_version: route_ref.profile_version
    }
  end

  def missing_raw_state_for_route_key(route_ref) do
    %{reason: :missing_raw_state_for_route_key, value_type: ExtensionDiagnostics.detailed_type_atom(route_ref)}
  end

  @spec target_route_unconfirmed(term(), RouteRef.t()) :: map()
  def target_route_unconfirmed(actual_route_key, %RouteRef{} = expected_route_ref) do
    %{
      reason: :target_route_unconfirmed,
      actual_route_key: route_key_name(actual_route_key),
      expected_route_key: route_key_name(expected_route_ref.route_key),
      expected_workflow_profile: expected_route_ref.profile_kind,
      expected_workflow_profile_version: expected_route_ref.profile_version
    }
  end

  @spec error(term()) :: map()
  def error(reason) when is_atom(reason) and not is_nil(reason), do: %{reason: reason}
  def error({:error, reason}), do: error(reason)

  def error({reason, detail}) when reason in [:transition_callback_failed, :invalid_transition_client_result] and is_map(detail) do
    detail
    |> Map.put_new(:code, reason)
    |> bounded_map()
  end

  def error(%_{} = exception), do: ExtensionDiagnostics.exception(exception)
  def error(reason) when is_map(reason), do: bounded_map(reason)
  def error(reason), do: %{reason_type: ExtensionDiagnostics.detailed_type_atom(reason)}

  defp bounded_map(map) do
    map
    |> Map.take([
      :code,
      :reason,
      :operation,
      :dependency,
      :expected_arity,
      :value_type,
      :reason_type,
      :kind,
      :exception,
      :target_route_key,
      :target_workflow_profile,
      :target_workflow_profile_version,
      :actual_route_key,
      :expected_route_key,
      :expected_workflow_profile,
      :expected_workflow_profile_version
    ])
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, key, bounded_value(value)) end)
    |> case do
      empty when map_size(empty) == 0 -> %{reason_type: :map}
      bounded -> bounded
    end
  end

  defp bounded_value(value) when is_atom(value) and not is_nil(value), do: value
  defp bounded_value(value) when is_binary(value), do: String.slice(value, 0, 128)
  defp bounded_value(value) when is_integer(value), do: value
  defp bounded_value(value) when is_boolean(value), do: value
  defp bounded_value(nil), do: nil
  defp bounded_value(value), do: "type:#{ExtensionDiagnostics.detailed_type_atom(value)}"

  defp route_key_name(route_key) when is_atom(route_key), do: Atom.to_string(route_key)
  defp route_key_name(route_key) when is_binary(route_key), do: route_key
  defp route_key_name(_route_key), do: nil
end
