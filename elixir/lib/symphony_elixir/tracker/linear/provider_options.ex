defmodule SymphonyElixir.Tracker.Linear.ProviderOptions do
  @moduledoc false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Linear.GraphQL
  alias SymphonyElixir.Tracker.Linear.Normalizer
  alias SymphonyElixir.Tracker.Linear.Queries

  @spec project_slug(map()) :: String.t() | nil
  def project_slug(tracker) when is_map(tracker) do
    tracker
    |> TrackerConfig.provider()
    |> provider_value("project_slug")
  end

  @spec routing_assignee_filter(map()) :: {:ok, map() | nil} | {:error, term()}
  def routing_assignee_filter(tracker) when is_map(tracker) do
    case assignee(tracker) do
      nil ->
        {:ok, nil}

      assignee ->
        build_assignee_filter(assignee, tracker)
    end
  end

  defp build_assignee_filter(assignee, tracker) when is_binary(assignee) and is_map(tracker) do
    case Normalizer.normalize_assignee_match_value(assignee) do
      nil ->
        {:ok, nil}

      "me" ->
        resolve_viewer_assignee_filter(tracker)

      normalized ->
        {:ok, %{configured_assignee: assignee, match_values: MapSet.new([normalized])}}
    end
  end

  defp resolve_viewer_assignee_filter(tracker) when is_map(tracker) do
    case GraphQL.request(Queries.viewer_query(), %{}, tracker: tracker) do
      {:ok, %{"data" => %{"viewer" => viewer}}} when is_map(viewer) ->
        case Normalizer.assignee_id(viewer) do
          nil ->
            {:error, :missing_linear_viewer_identity}

          viewer_id ->
            {:ok, %{configured_assignee: "me", match_values: MapSet.new([viewer_id])}}
        end

      {:ok, _body} ->
        {:error, :missing_linear_viewer_identity}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assignee(tracker) when is_map(tracker) do
    tracker
    |> TrackerConfig.provider()
    |> provider_value("assignee")
  end

  defp provider_value(provider, key) when is_map(provider) and is_binary(key) do
    Map.get(provider, key) || map_get_existing_atom(provider, key)
  end

  defp provider_value(_provider, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
