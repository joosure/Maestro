defmodule SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Observation do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Fields

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

  @spec signature(map()) :: term()
  def signature(facts) when is_map(facts) do
    %{
      provider_state: map_value(facts, Fields.provider_state()),
      review_summary: map_value(facts, Fields.review_summary()),
      check_summary: map_value(facts, Fields.check_summary()),
      mergeability_summary: map_value(facts, Fields.mergeability_summary()),
      unresolved_actionable_feedback?: map_value(facts, Fields.unresolved_actionable_feedback()),
      number: map_value(facts, Fields.number()),
      url: map_value(facts, Fields.url()),
      branch: map_value(facts, Fields.branch()),
      head_sha: map_value(facts, Fields.head_sha()),
      error: normalized_error(map_value(facts, Fields.error())),
      retryable?: map_value(facts, Fields.retryable())
    }
  end

  defp normalized_error(nil), do: nil
  defp normalized_error(%{code: code, operation: operation}), do: {operation, code}
  defp normalized_error(%{__struct__: struct} = error), do: {struct, Map.get(error, :operation), Map.get(error, :code)}
  defp normalized_error(error), do: inspect(error)

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    value(map, key)
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
