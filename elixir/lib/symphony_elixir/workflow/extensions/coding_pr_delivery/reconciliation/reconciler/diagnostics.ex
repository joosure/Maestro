defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Diagnostics do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics, as: ExtensionDiagnostics

  @spec invalid_options(term()) :: map()
  def invalid_options(opts), do: %{reason: :invalid_options, value_type: ExtensionDiagnostics.detailed_type_atom(opts)}

  @spec invalid_dependency(atom(), term(), non_neg_integer() | [non_neg_integer()]) :: map()
  def invalid_dependency(name, value, arity) when is_atom(name) do
    %{
      reason: :invalid_dependency,
      dependency: Atom.to_string(name),
      expected_arity: expected_arity(arity),
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

  @spec invalid_result(atom(), term()) :: map()
  def invalid_result(operation, value) when is_atom(operation) do
    %{
      reason: :invalid_result,
      operation: operation,
      value_type: ExtensionDiagnostics.detailed_type_atom(value)
    }
  end

  @spec reason_fields(term()) :: map()
  def reason_fields(reason) when is_atom(reason) and not is_nil(reason), do: %{reason: reason}
  def reason_fields({:error, reason}), do: reason_fields(reason)

  def reason_fields({reason, detail}) when reason in [:reconciler_callback_failed, :invalid_reconciler_client_result] and is_map(detail) do
    detail
    |> Map.put_new(:code, reason)
    |> bounded_map()
  end

  def reason_fields({reason, detail}) when is_atom(reason) and not is_nil(reason) do
    %{reason: reason, detail_type: ExtensionDiagnostics.detailed_type_atom(detail)}
  end

  def reason_fields(%_{} = error), do: ExtensionDiagnostics.exception(error)
  def reason_fields(reason) when is_map(reason), do: bounded_map(reason)
  def reason_fields(reason), do: %{reason_type: ExtensionDiagnostics.type_name(reason)}

  @spec error_string(term()) :: String.t()
  def error_string(reason) do
    reason
    |> reason_fields()
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{value_string(value)}" end)
  end

  defp expected_arity(arities) when is_list(arities) do
    arities
    |> Enum.map_join("|", &Integer.to_string/1)
  end

  defp expected_arity(arity) when is_integer(arity), do: arity

  defp bounded_map(map) do
    map
    |> Map.take([
      :code,
      :reason,
      :operation,
      :value_type,
      :reason_type,
      :detail_type,
      :kind,
      :exception,
      :dependency,
      :expected_arity
    ])
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, key, bounded_value(value)) end)
    |> case do
      empty when map_size(empty) == 0 -> %{reason_type: :map}
      bounded -> bounded
    end
  end

  defp bounded_value(value) when is_atom(value) and not is_nil(value), do: value
  defp bounded_value(value) when is_binary(value), do: String.slice(value, 0, 128)
  defp bounded_value(value) when is_boolean(value), do: value
  defp bounded_value(value) when is_integer(value), do: value
  defp bounded_value(nil), do: nil
  defp bounded_value(value), do: "type:#{ExtensionDiagnostics.detailed_type_atom(value)}"

  defp value_string(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp value_string(value) when is_binary(value), do: value
  defp value_string(value) when is_boolean(value), do: to_string(value)
  defp value_string(value) when is_integer(value), do: Integer.to_string(value)
  defp value_string(nil), do: "nil"
  defp value_string(value), do: "type:#{ExtensionDiagnostics.detailed_type_atom(value)}"
end
