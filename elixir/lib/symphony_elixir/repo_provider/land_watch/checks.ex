defmodule SymphonyElixir.RepoProvider.LandWatch.Checks do
  @moduledoc false

  @success_conclusions ~w(success skipped neutral)

  @type summary :: %{
          pending?: boolean(),
          failed?: boolean(),
          failures: [String.t()]
        }

  @spec summarize([map()]) :: summary()
  def summarize([]) do
    %{pending?: true, failed?: false, failures: ["no checks reported"]}
  end

  def summarize(check_runs) when is_list(check_runs) do
    check_runs
    |> dedupe()
    |> Enum.reduce(%{pending?: false, failed?: false, failures: []}, fn check, acc ->
      status = field_value(check, "status")
      conclusion = field_value(check, "conclusion")
      name = field_value(check, "name") || "unknown"

      cond do
        status != "completed" ->
          %{acc | pending?: true}

        conclusion in @success_conclusions ->
          acc

        true ->
          %{acc | failed?: true, failures: acc.failures ++ ["#{name}: #{conclusion}"]}
      end
    end)
  end

  @spec dedupe([map()]) :: [map()]
  def dedupe(check_runs) when is_list(check_runs) do
    check_runs
    |> Enum.reduce(%{}, fn check, latest_by_name ->
      name = field_value(check, "name") || "unknown"
      timestamp = check_timestamp(check)
      existing = Map.get(latest_by_name, name)

      cond do
        is_nil(existing) ->
          Map.put(latest_by_name, name, check)

        is_nil(timestamp) ->
          latest_by_name

        replace_existing?(timestamp, check_timestamp(existing)) ->
          Map.put(latest_by_name, name, check)

        true ->
          latest_by_name
      end
    end)
    |> Map.values()
  end

  @spec check_timestamp(map()) :: DateTime.t() | nil
  def check_timestamp(check) when is_map(check) do
    ["completed_at", "started_at", "run_started_at", "created_at"]
    |> Enum.find_value(fn key ->
      case field_value(check, key) do
        value when is_binary(value) and value != "" -> parse_time(value)
        _other -> nil
      end
    end)
  end

  @spec parse_time(String.t()) :: DateTime.t() | nil
  def parse_time(value) when is_binary(value) do
    value
    |> String.replace_suffix("Z", "+00:00")
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp replace_existing?(_timestamp, nil), do: true

  defp replace_existing?(timestamp, existing_timestamp) do
    DateTime.compare(timestamp, existing_timestamp) == :gt
  end

  defp field_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
