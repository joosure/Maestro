defmodule SymphonyElixir.Tracker.Tapd.Normalizer do
  @moduledoc """
  Normalizes TAPD Story payloads into `SymphonyElixir.Issue`.
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @spec normalize_story(map(), keyword()) :: Issue.t() | nil
  def normalize_story(story, opts \\ [])

  def normalize_story(story, opts) when is_map(story) and is_list(opts) do
    story_id = string_field(story, "id")
    state_phase_map = Keyword.get(opts, :state_phase_map, %{})
    state = string_field(story, "status")
    workflow = Keyword.get(opts, :workflow, %{})
    workitem_type_id = string_field(story, "workitem_type_id")

    blocked_by =
      merge_blockers(
        extract_blockers(story, state_phase_map),
        Keyword.get(opts, :blocked_by, [])
      )

    %Issue{
      id: story_id,
      identifier: story_identifier(story_id),
      title: string_field(story, "name") || string_field(story, "title"),
      description: string_field(story, "description"),
      priority: parse_priority(string_field(story, "priority")),
      state: state,
      lifecycle_phase: WorkflowLifecycle.phase_for_state(state, state_phase_map),
      workitem_type_id: normalize_string(workitem_type_id),
      branch_name: nil,
      url: Keyword.get(opts, :workspace_url),
      assignee_id: nil,
      blocked_by: blocked_by,
      labels: extract_labels(story),
      workflow: workflow,
      assigned_to_worker: true,
      created_at: parse_datetime(string_field(story, "created")),
      updated_at: parse_datetime(string_field(story, "modified") || string_field(story, "updated"))
    }
  end

  def normalize_story(_story, _opts), do: nil

  defp story_identifier(nil), do: nil
  defp story_identifier(story_id), do: "TAPD-" <> story_id

  defp extract_labels(story) do
    case Map.get(story, "labels") || Map.get(story, "label") do
      values when is_list(values) ->
        values
        |> Enum.map(&normalize_string/1)
        |> Enum.reject(&is_nil/1)

      values when is_binary(values) ->
        values
        |> String.split(",", trim: true)
        |> Enum.map(&normalize_string/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_blockers(story, state_phase_map) do
    story
    |> Map.take(["blocked_by", "blockers", "dependencies"])
    |> Map.values()
    |> Enum.flat_map(&normalize_blocker_value(&1, state_phase_map))
  end

  defp normalize_blocker_value(values, state_phase_map) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_blocker_value(&1, state_phase_map))
  end

  defp normalize_blocker_value(%{} = blocker, state_phase_map) do
    blocker_id = string_field(blocker, "id")
    blocker_state = string_field(blocker, "status")

    if is_nil(blocker_id) do
      []
    else
      [
        %{
          id: blocker_id,
          identifier: story_identifier(blocker_id),
          state: blocker_state,
          lifecycle_phase: WorkflowLifecycle.phase_for_state(blocker_state, state_phase_map)
        }
      ]
    end
  end

  defp normalize_blocker_value(value, _state_phase_map) when is_binary(value) do
    case normalize_string(value) do
      nil ->
        []

      blocker_id ->
        [
          %{
            id: blocker_id,
            identifier: story_identifier(blocker_id),
            state: nil,
            lifecycle_phase: nil
          }
        ]
    end
  end

  defp normalize_blocker_value(_value, _state_phase_map), do: []

  defp merge_blockers(existing_blockers, additional_blockers) do
    (existing_blockers ++ List.wrap(additional_blockers))
    |> Enum.reduce([], fn
      %{id: blocker_id} = blocker, acc when is_binary(blocker_id) ->
        merge_blocker(acc, blocker_id, blocker)

      _blocker, acc ->
        acc
    end)
  end

  defp merge_blocker(acc, blocker_id, blocker) do
    case Enum.find_index(acc, &(&1.id == blocker_id)) do
      nil ->
        acc ++ [blocker]

      index ->
        List.update_at(acc, index, fn existing ->
          existing
          |> Map.put_new(:identifier, blocker[:identifier])
          |> maybe_put_value(:state, blocker[:state])
          |> maybe_put_value(:lifecycle_phase, blocker[:lifecycle_phase])
        end)
    end
  end

  defp maybe_put_value(map, _key, nil), do: map

  defp maybe_put_value(map, key, value) do
    case Map.get(map, key) do
      nil -> Map.put(map, key, value)
      _existing -> map
    end
  end

  defp string_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(value), do: if(value in [nil, ""], do: nil, else: to_string(value))

  defp parse_priority(nil), do: nil
  defp parse_priority(value) when is_integer(value), do: value

  defp parse_priority(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {priority, ""} -> priority
      _ -> nil
    end
  end

  defp parse_priority(_value), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        nil
    end
  end

  defp parse_datetime(_value), do: nil
end
