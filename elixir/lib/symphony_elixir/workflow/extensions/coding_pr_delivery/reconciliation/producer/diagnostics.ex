defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics, as: ExtensionDiagnostics

  @spec reason_fields(term()) :: map()
  def reason_fields(reason) when is_atom(reason) and not is_nil(reason), do: %{reason: reason}

  def reason_fields({reason, detail}) when is_atom(reason) and not is_nil(reason) do
    %{reason: reason, detail_type: ExtensionDiagnostics.type_name(detail)}
  end

  def reason_fields({:error, reason}), do: reason_fields(reason)
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

  @spec invalid_options(term()) :: map()
  def invalid_options(opts), do: %{reason: :invalid_options, value_type: ExtensionDiagnostics.type_name(opts)}

  @spec invalid_dependency(atom(), term(), non_neg_integer()) :: map()
  def invalid_dependency(name, value, arity) when is_atom(name) and is_integer(arity) and arity >= 0 do
    %{
      reason: :invalid_dependency,
      dependency: Atom.to_string(name),
      expected_arity: arity,
      value_type: ExtensionDiagnostics.type_name(value)
    }
  end

  @spec invalid_app_config(atom(), term()) :: map()
  def invalid_app_config(key, value) when is_atom(key) do
    %{reason: :invalid_app_config, config_key: Atom.to_string(key), value_type: ExtensionDiagnostics.type_name(value)}
  end

  defp bounded_map(map) do
    map
    |> Map.take([
      :code,
      :reason,
      :value_type,
      :field,
      :expected,
      :expected_arity,
      :kind,
      :exception,
      :reason_type,
      :dependency
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
  defp bounded_value(value), do: "type:#{ExtensionDiagnostics.type_name(value)}"

  defp value_string(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp value_string(value) when is_binary(value), do: value
  defp value_string(value) when is_boolean(value), do: to_string(value)
  defp value_string(value) when is_integer(value), do: Integer.to_string(value)
  defp value_string(nil), do: "nil"
  defp value_string(value), do: "type:#{ExtensionDiagnostics.type_name(value)}"
end
