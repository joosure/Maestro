defmodule SymphonyElixir.Tracker.Tapd.Client.StoryPayload do
  @moduledoc false

  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Tapd.Client.{Fields, Response, WorkitemTypeScope}
  alias SymphonyElixir.Tracker.Tapd.{Normalizer, WorkflowConfig}

  @spec decode(String.t(), term(), map(), function(), keyword()) ::
          {:ok, [SymphonyElixir.Issue.t()], non_neg_integer(), [String.t()]} | {:error, term()}
  def decode(path, body, tracker, request_fun, opts \\ []) when is_binary(path) and is_map(tracker) do
    validate_workitem_types? = Keyword.get(opts, :validate_workitem_types?, true)

    with {:ok, data} <- Response.decode_success_envelope(path, body),
         true <- is_list(data) || {:error, {:unexpected_tapd_payload, path, body}},
         {:ok, raw_stories} <- unwrap_story_list(path, data, body),
         {:ok, filtered_stories, observed_workitem_type_ids} <-
           WorkitemTypeScope.resolve(raw_stories, tracker),
         :ok <-
           WorkitemTypeScope.maybe_validate(
             observed_workitem_type_ids,
             tracker,
             request_fun,
             validate_workitem_types?
           ) do
      workspace_url = Tracker.project_url(tracker)

      {:ok,
       Enum.map(filtered_stories, fn story ->
         workflow =
           WorkflowConfig.workflow_for_story(tracker, story) ||
             WorkflowConfig.global_workflow(
               tracker,
               Fields.normalize_string(Fields.string_field(story, "workitem_type_id"))
             )

         Normalizer.normalize_story(story,
           workspace_url: workspace_url,
           state_phase_map: Map.get(workflow, :state_phase_map, %{}),
           workflow: workflow
         )
       end), length(raw_stories), observed_workitem_type_ids}
    end
  end

  defp unwrap_story_list(path, data, body) when is_list(data) do
    data
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case unwrap_story_node(entry) do
        {:ok, story} -> {:cont, {:ok, acc ++ [story]}}
        :error -> {:halt, {:error, {:unexpected_tapd_payload, path, body}}}
      end
    end)
  end

  defp unwrap_story_node(%{"Story" => %{} = story}), do: {:ok, story}
  defp unwrap_story_node(%{Story: %{} = story}), do: {:ok, story}

  defp unwrap_story_node(%{} = story) do
    if is_binary(Fields.string_field(story, "id")) do
      {:ok, Fields.normalize_keys_to_strings(story)}
    else
      :error
    end
  end

  defp unwrap_story_node(_entry), do: :error
end
