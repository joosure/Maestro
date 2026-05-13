defmodule SymphonyElixir.Agent.Credential.Store.Usage do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Store.{Normalization, State}

  @token_keys ["input_tokens", "output_tokens", "total_tokens"]

  @spec apply_token_delta(map(), map(), DateTime.t()) :: map()
  def apply_token_delta(state, token_delta, %DateTime{} = timestamp)
      when is_map(state) and is_map(token_delta) do
    delta = normalize_usage_delta(token_delta)

    state
    |> Map.put(
      "token_totals",
      update_usage_totals(Map.get(state, "token_totals", %{}), delta, timestamp)
    )
    |> Map.put(
      "rate_limit_periods",
      update_rate_limit_period_token_totals(Map.get(state, "rate_limit_periods", %{}), delta)
    )
    |> Map.put("updated_at", Normalization.now_iso())
  end

  @spec normalize_usage_delta(map()) :: map()
  def normalize_usage_delta(delta) do
    %{
      "input_tokens" => usage_value(delta, [:input_tokens, "input_tokens", :input, "input"]),
      "output_tokens" => usage_value(delta, [:output_tokens, "output_tokens", :output, "output"]),
      "total_tokens" => usage_value(delta, [:total_tokens, "total_tokens", :total, "total"])
    }
  end

  defp usage_value(delta, keys) do
    keys
    |> Enum.find_value(&Map.get(delta, &1))
    |> Normalization.integer_value()
  end

  defp update_usage_totals(token_totals, delta, timestamp) do
    daily_period = timestamp |> DateTime.to_date() |> Date.to_iso8601()

    token_totals
    |> Map.merge(State.default_token_totals(), fn _key, _default, value -> value end)
    |> update_usage_period("total", nil, delta)
    |> update_usage_period("daily", daily_period, delta)
  end

  defp update_usage_period(token_totals, key, period, delta) do
    current = Map.get(token_totals, key, %{})

    current =
      if is_nil(period) or Map.get(current, "period") == period,
        do: current,
        else: %{"period" => period}

    updated =
      Enum.reduce(@token_keys, current, fn token_key, acc ->
        Map.put(
          acc,
          token_key,
          Normalization.integer_value(Map.get(acc, token_key)) +
            Normalization.integer_value(Map.get(delta, token_key))
        )
      end)

    updated = if is_nil(period), do: updated, else: Map.put(updated, "period", period)
    Map.put(token_totals, key, updated)
  end

  defp update_rate_limit_period_token_totals(periods, delta)
       when is_map(periods) and is_map(delta) do
    Enum.reduce(periods, %{}, fn {bucket, period}, acc ->
      updated =
        Enum.reduce(@token_keys, period, fn token_key, period_acc ->
          Map.put(
            period_acc,
            token_key,
            Normalization.integer_value(Map.get(period_acc, token_key)) +
              Normalization.integer_value(Map.get(delta, token_key))
          )
        end)

      Map.put(acc, bucket, updated)
    end)
  end

  defp update_rate_limit_period_token_totals(_periods, _delta), do: %{}
end
