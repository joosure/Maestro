defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Payload
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary.{Checks, Feedback, Reviews}

  @spec provider_state(map()) :: :closed | :merged | :open | :unknown
  def provider_state(payload) when is_map(payload) do
    merged? =
      Payload.field_value(payload, Contract.payload_key(:merged)) == true or
        Payload.present?(Payload.field_value(payload, Contract.payload_key(:merged_at)))

    cond do
      merged? ->
        :merged

      true ->
        Contract.provider_state_by_name()
        |> Map.get(payload |> Payload.field_value(Contract.payload_key(:state)) |> Payload.normalize_token(), :unknown)
    end
  end

  @spec review_summary([map()]) :: :approved | :changes_requested | :pending
  defdelegate review_summary(reviews), to: Reviews, as: :summary

  @spec check_summary([map()]) :: :absent | :failing | :passing | :pending
  defdelegate check_summary(check_runs), to: Checks, as: :summary

  @spec mergeability_summary(map()) :: :blocked | :conflicting | :mergeable | :unknown
  def mergeability_summary(payload) when is_map(payload) do
    mergeable = payload |> Payload.field_value(Contract.payload_key(:mergeable)) |> Payload.normalize_token()
    merge_state = payload |> Payload.field_value(Contract.payload_key(:merge_state_status)) |> Payload.normalize_token()

    cond do
      mergeable == Contract.mergeability(:conflicting) or merge_state == Contract.mergeability(:dirty) ->
        :conflicting

      merge_state in Contract.blocked_merge_states() ->
        :blocked

      mergeable == Contract.mergeability(:mergeable) and merge_state in Contract.mergeable_merge_states() ->
        :mergeable

      merge_state in Contract.fallback_mergeable_merge_states() ->
        :mergeable

      true ->
        :unknown
    end
  end

  @spec unresolved_actionable_feedback?([map()], [map()], map() | list()) :: boolean()
  defdelegate unresolved_actionable_feedback?(issue_comments, review_comments, env), to: Feedback
end
