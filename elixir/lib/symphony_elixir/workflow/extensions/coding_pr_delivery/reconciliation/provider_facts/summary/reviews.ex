defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary.Reviews do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Payload

  @spec summary([map()]) :: :approved | :changes_requested | :pending
  def summary(reviews) when is_list(reviews) do
    latest_reviews = latest_by_user(reviews)

    cond do
      Enum.any?(latest_reviews, &(state(&1) == Contract.review_state(:changes_requested))) ->
        :changes_requested

      Enum.any?(latest_reviews, &(state(&1) == Contract.review_state(:approved))) ->
        :approved

      true ->
        :pending
    end
  end

  defp latest_by_user(reviews) do
    reviews
    |> Enum.reduce(%{}, fn review, latest ->
      user = review |> Payload.field_value(Contract.payload_key(:user)) |> user_login()

      cond do
        user == "" -> latest
        replace?(review, Map.get(latest, user)) -> Map.put(latest, user, review)
        true -> latest
      end
    end)
    |> Map.values()
  end

  defp replace?(_review, nil), do: true

  defp replace?(review, existing_review) do
    case {time(review), time(existing_review)} do
      {%DateTime{} = left, %DateTime{} = right} -> DateTime.compare(left, right) == :gt
      {%DateTime{}, nil} -> true
      _other -> false
    end
  end

  defp state(review) when is_map(review) do
    review
    |> Payload.field_value(Contract.payload_key(:state))
    |> Payload.normalize_token()
  end

  defp time(review) when is_map(review) do
    case Payload.field_value(review, Contract.payload_key(:submitted_at)) ||
           Payload.field_value(review, Contract.payload_key(:created_at)) do
      value when is_binary(value) -> parse_time(value)
      _value -> nil
    end
  end

  defp parse_time(value) when is_binary(value) do
    value
    |> String.replace_suffix(Contract.utc_suffix(), Contract.utc_offset())
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp user_login(user) when is_map(user) do
    user
    |> Payload.field_value(Contract.payload_key(:login))
    |> to_string()
  end

  defp user_login(_user), do: ""
end
