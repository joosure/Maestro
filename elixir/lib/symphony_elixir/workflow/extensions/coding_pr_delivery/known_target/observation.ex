defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Observation do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields

  @signature_error_operation_key "operation"
  @signature_error_code_key "code"
  @signature_struct_key "struct"
  @signature_unsupported_type_key "unsupported_type"
  @signature_unsupported_key_prefix "unsupported_key:"

  @spec attrs(map()) :: map()
  def attrs(facts) when is_map(facts) do
    %{
      Fields.number() => map_value(facts, Fields.number()),
      Fields.url() => map_value(facts, Fields.url()),
      Fields.branch() => map_value(facts, Fields.branch()),
      Fields.head_sha() => map_value(facts, Fields.head_sha()),
      Fields.last_observed_at() => map_value(facts, Fields.observed_at()),
      Fields.last_observed_signature() => signature(facts)
    }
  end

  @spec signature(map()) :: map()
  def signature(facts) when is_map(facts) do
    %{
      Fields.provider_state() => signature_value(map_value(facts, Fields.provider_state())),
      Fields.review_summary() => signature_value(map_value(facts, Fields.review_summary())),
      Fields.check_summary() => signature_value(map_value(facts, Fields.check_summary())),
      Fields.mergeability_summary() => signature_value(map_value(facts, Fields.mergeability_summary())),
      Fields.unresolved_actionable_feedback() => signature_value(map_value(facts, Fields.unresolved_actionable_feedback())),
      Fields.number() => signature_value(map_value(facts, Fields.number())),
      Fields.url() => signature_value(map_value(facts, Fields.url())),
      Fields.branch() => signature_value(map_value(facts, Fields.branch())),
      Fields.head_sha() => signature_value(map_value(facts, Fields.head_sha())),
      Fields.error() => normalized_error(map_value(facts, Fields.error())),
      Fields.retryable() => signature_value(map_value(facts, Fields.retryable()))
    }
  end

  defp normalized_error(nil), do: nil

  defp normalized_error(%{code: code, operation: operation}) do
    %{
      @signature_error_operation_key => signature_value(operation),
      @signature_error_code_key => signature_value(code)
    }
  end

  defp normalized_error(%{__struct__: struct} = error) do
    %{
      @signature_struct_key => Atom.to_string(struct),
      @signature_error_operation_key => signature_value(Map.get(error, :operation)),
      @signature_error_code_key => signature_value(Map.get(error, :code))
    }
  end

  defp normalized_error(error), do: %{@signature_unsupported_type_key => type_label(error)}

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key)
  end

  defp signature_value(value) when is_struct(value), do: %{@signature_struct_key => Atom.to_string(value.__struct__)}

  defp signature_value(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {signature_key(key), signature_value(nested_value)}
    end)
  end

  defp signature_value(value) when is_list(value), do: Enum.map(value, &signature_value/1)
  defp signature_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&signature_value/1)
  defp signature_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp signature_value(value) when is_binary(value), do: value
  defp signature_value(value) when is_boolean(value), do: value
  defp signature_value(value) when is_integer(value), do: value
  defp signature_value(value) when is_float(value), do: value
  defp signature_value(nil), do: nil
  defp signature_value(value), do: %{@signature_unsupported_type_key => type_label(value)}

  defp signature_key(key) when is_binary(key), do: key
  defp signature_key(key) when is_atom(key), do: Atom.to_string(key)
  defp signature_key(key), do: @signature_unsupported_key_prefix <> type_label(key)

  defp type_label(value), do: value |> Diagnostics.detailed_type_atom() |> Atom.to_string()
end
