defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary.Checks do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CheckRun
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Contract

  @timestamp_keys [
    :completed_at,
    :started_at,
    :run_started_at,
    :created_at
  ]

  @spec summary([map()]) :: :absent | :failing | :passing | :pending
  def summary([]), do: :absent

  def summary(check_runs) when is_list(check_runs) do
    case summarize(check_runs) do
      %{failed?: true} -> :failing
      %{pending?: true} -> :pending
      %{pending?: false} -> :passing
    end
  end

  defp summarize(check_runs) when is_list(check_runs) do
    check_runs
    |> dedupe()
    |> Enum.reduce(%{pending?: false, failed?: false}, fn check, acc ->
      cond do
        not CheckRun.completed?(check) ->
          %{acc | pending?: true}

        CheckRun.successful_conclusion?(CheckRun.conclusion(check)) ->
          acc

        true ->
          %{acc | failed?: true}
      end
    end)
  end

  defp dedupe(check_runs) when is_list(check_runs) do
    check_runs
    |> Enum.reduce(%{}, fn check, latest_by_name ->
      name = CheckRun.name(check)
      timestamp = timestamp(check)
      existing = Map.get(latest_by_name, name)

      cond do
        is_nil(existing) ->
          Map.put(latest_by_name, name, check)

        is_nil(timestamp) ->
          latest_by_name

        after_time?(timestamp, timestamp(existing)) ->
          Map.put(latest_by_name, name, check)

        true ->
          latest_by_name
      end
    end)
    |> Map.values()
  end

  defp timestamp(check) when is_map(check) do
    Enum.find_value(@timestamp_keys, fn key ->
      case CheckRun.field(check, Contract.payload_key(key)) do
        value when is_binary(value) and value != "" -> parse_time(value)
        _other -> nil
      end
    end)
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

  defp after_time?(_left, nil), do: true
  defp after_time?(nil, _right), do: false
  defp after_time?(left, right), do: DateTime.compare(left, right) == :gt
end
