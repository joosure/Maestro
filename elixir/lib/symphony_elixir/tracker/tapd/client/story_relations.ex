defmodule SymphonyElixir.Tracker.Tapd.Client.StoryRelations do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Tapd.Client.{Fields, Request, Response}

  @request_timeout_ms 30_000
  @id_fetch_max_concurrency 4
  @relation_fetch_max_concurrency 4

  @spec enrich_issues([Issue.t()], map(), function(), function()) :: {:ok, [Issue.t()]} | {:error, term()}
  def enrich_issues([], _tracker, _request_fun, _fetch_story_by_id_fun), do: {:ok, []}

  def enrich_issues(issues, tracker, request_fun, fetch_story_by_id_fun) when is_list(issues) do
    with {:ok, blockers_by_issue_id} <-
           fetch_story_blockers_by_issue_id(issues, tracker, request_fun),
         {:ok, blocker_states_by_id} <-
           fetch_blocker_states_by_id(blockers_by_issue_id, tracker, request_fun, fetch_story_by_id_fun) do
      {:ok,
       Enum.map(issues, fn %Issue{} = issue ->
         relation_blockers =
           blockers_by_issue_id
           |> Map.get(issue.id, [])
           |> Enum.map(fn blocker ->
             blocker_details = Map.get(blocker_states_by_id, blocker.id, %{})

             blocker
             |> Map.put(:state, Map.get(blocker_details, :state))
             |> Map.put(:lifecycle_phase, Map.get(blocker_details, :lifecycle_phase))
           end)

         %{issue | blocked_by: merge_blockers(issue.blocked_by, relation_blockers)}
       end)}
    end
  end

  defp fetch_story_blockers_by_issue_id(issues, tracker, request_fun) do
    issues
    |> Task.async_stream(
      fn %Issue{id: issue_id} = issue ->
        with {:ok, blockers} <- fetch_story_time_blockers(issue_id, tracker, request_fun) do
          {:ok, issue.id, merge_blockers(issue.blocked_by, blockers)}
        end
      end,
      max_concurrency: @relation_fetch_max_concurrency,
      ordered: true,
      timeout: @request_timeout_ms + 1_000
    )
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {:ok, issue_id, blockers}}, {:ok, acc} ->
        {:cont, {:ok, Map.put(acc, issue_id, blockers)}}

      {:ok, {:error, _reason}}, {:ok, acc} ->
        {:cont, {:ok, acc}}

      {:exit, _reason}, {:ok, acc} ->
        {:cont, {:ok, acc}}
    end)
  end

  defp fetch_blocker_states_by_id(blockers_by_issue_id, tracker, request_fun, fetch_story_by_id_fun)
       when is_map(blockers_by_issue_id) do
    blocker_ids =
      blockers_by_issue_id
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&Map.get(&1, :id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case blocker_ids do
      [] ->
        {:ok, %{}}

      _ ->
        {:ok, fetch_blocker_state_map(blocker_ids, tracker, request_fun, fetch_story_by_id_fun)}
    end
  end

  defp fetch_blocker_state_map(blocker_ids, tracker, request_fun, fetch_story_by_id_fun)
       when is_list(blocker_ids) do
    blocker_ids
    |> Task.async_stream(
      fn blocker_id ->
        fetch_story_by_id_fun.(blocker_id, tracker, request_fun)
      end,
      max_concurrency: @id_fetch_max_concurrency,
      ordered: true,
      timeout: @request_timeout_ms + 1_000
    )
    |> Enum.reduce(%{}, fn
      {:ok, {:ok, blocker_issues}}, acc ->
        Enum.reduce(blocker_issues, acc, fn %Issue{} = issue, issue_acc ->
          Map.put(issue_acc, issue.id, %{
            state: issue.state,
            lifecycle_phase: issue.lifecycle_phase
          })
        end)

      {:ok, {:error, _reason}}, acc ->
        acc

      {:exit, _reason}, acc ->
        acc
    end)
  end

  defp fetch_story_time_blockers(story_id, tracker, request_fun) when is_binary(story_id) do
    with {:ok, body} <-
           Request.request("GET", "/stories/get_time_relative_stories", %{"story_id" => story_id},
             tracker: tracker,
             request_fun: request_fun
           ),
         {:ok, data} <- Response.decode_success_envelope("/stories/get_time_relative_stories", body),
         {:ok, blockers} <- decode_story_time_blockers(story_id, data, body) do
      {:ok, blockers}
    end
  end

  defp decode_story_time_blockers(_story_id, [], _body), do: {:ok, []}

  defp decode_story_time_blockers(story_id, data, body) when is_list(data) do
    data
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case decode_story_time_blocker_entry(story_id, entry) do
        {:ok, blockers} ->
          {:cont, {:ok, acc ++ blockers}}

        :error ->
          {:halt, {:error, {:unexpected_tapd_payload, "/stories/get_time_relative_stories", body}}}
      end
    end)
    |> case do
      {:ok, blockers} -> {:ok, merge_blockers([], blockers)}
      error -> error
    end
  end

  defp decode_story_time_blockers(_story_id, _data, body),
    do: {:error, {:unexpected_tapd_payload, "/stories/get_time_relative_stories", body}}

  defp decode_story_time_blocker_entry(story_id, %{"WorkitemTimeRelation" => %{} = relation}),
    do: decode_story_time_blocker_entry(story_id, relation)

  defp decode_story_time_blocker_entry(story_id, %{WorkitemTimeRelation: %{} = relation}),
    do: decode_story_time_blocker_entry(story_id, relation)

  defp decode_story_time_blocker_entry(story_id, %{} = relation) do
    normalized_relation = Fields.normalize_keys_to_strings(relation)
    relation_story_id = Fields.normalize_string(Fields.string_field(normalized_relation, "dst_workitem_id"))
    blocker_id = Fields.normalize_string(Fields.string_field(normalized_relation, "workitem_id"))

    cond do
      relation_story_id == story_id and is_binary(blocker_id) and blocker_id != story_id ->
        {:ok, [%{id: blocker_id, identifier: "TAPD-" <> blocker_id, state: nil, lifecycle_phase: nil}]}

      is_binary(relation_story_id) and is_binary(blocker_id) ->
        {:ok, []}

      true ->
        :error
    end
  end

  defp decode_story_time_blocker_entry(_story_id, _entry), do: :error

  defp merge_blockers(existing_blockers, additional_blockers) do
    (List.wrap(existing_blockers) ++ List.wrap(additional_blockers))
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
end
