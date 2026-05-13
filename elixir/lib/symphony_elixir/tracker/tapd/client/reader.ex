defmodule SymphonyElixir.Tracker.Tapd.Client.Reader do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Tapd.Client.{Errors, Fields, Request, StoryPayload, StoryRelations, WorkitemTypeScope}
  alias SymphonyElixir.Tracker.Tapd.WorkflowConfig

  @page_limit 100
  @request_timeout_ms 30_000
  @id_fetch_max_concurrency 4

  @spec fetch_candidate_issues(map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(tracker) when is_map(tracker) do
    case TrackerConfig.active_states(tracker) do
      state_names when is_list(state_names) ->
        fetch_stories_by_status(state_names, tracker: tracker)
        |> Errors.map_result(:fetch_candidate_issues)

      _other ->
        {:error, Errors.normalize(:fetch_candidate_issues, :missing_tapd_active_states)}
    end
  end

  @spec fetch_issues_by_states([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names, tracker) when is_list(state_names) and is_map(tracker) do
    fetch_stories_by_status(state_names, tracker: tracker)
    |> Errors.map_result(:fetch_issues_by_states)
  end

  @spec fetch_issue_states_by_ids([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, tracker) when is_list(issue_ids) and is_map(tracker) do
    fetch_stories_by_ids(issue_ids, tracker: tracker)
    |> Errors.map_result(:fetch_issue_states_by_ids)
  end

  @spec fetch_stories_by_status([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_stories_by_status(state_names, opts \\ [])
      when is_list(state_names) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    operation = Keyword.get(opts, :operation, :fetch_issues_by_states)
    request_fun = Keyword.get(opts, :request_fun, &Request.default_request/1)

    statuses =
      state_names
      |> Enum.map(&Fields.normalize_string/1)
      |> Enum.reject(&is_nil/1)

    result =
      case statuses do
        [] ->
          {:ok, []}

        _ ->
          with {:ok, issues} <-
                 do_fetch_stories_by_status(
                   tracker,
                   Enum.join(statuses, "|"),
                   1,
                   [],
                   [],
                   request_fun
                 ) do
            StoryRelations.enrich_issues(issues, tracker, request_fun, &fetch_story_by_id/3)
          end
      end

    Errors.map_result(result, operation)
  end

  @spec fetch_stories_by_ids([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_stories_by_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    operation = Keyword.get(opts, :operation, :fetch_issue_states_by_ids)
    request_fun = Keyword.get(opts, :request_fun, &Request.default_request/1)

    result =
      issue_ids
      |> Enum.map(&Fields.normalize_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> do_fetch_stories_by_ids(tracker, request_fun)
      |> case do
        {:ok, issues} -> StoryRelations.enrich_issues(issues, tracker, request_fun, &fetch_story_by_id/3)
        error -> error
      end

    Errors.map_result(result, operation)
  end

  @spec fetch_story_by_id(String.t(), map(), function()) :: {:ok, [Issue.t()]} | {:error, term()}
  defp fetch_story_by_id(issue_id, tracker, request_fun) do
    case Request.request("GET", "/stories", %{"id" => issue_id},
           tracker: tracker,
           request_fun: request_fun
         ) do
      {:ok, body} ->
        case StoryPayload.decode("/stories", body, tracker, request_fun, validate_workitem_types?: false) do
          {:ok, issues, _raw_count, _observed_workitem_type_ids} -> {:ok, issues}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_fetch_stories_by_status(
         tracker,
         status_filter,
         page,
         acc,
         observed_workitem_type_ids,
         request_fun
       ) do
    params =
      %{
        "status" => status_filter,
        "page" => page,
        "limit" => @page_limit
      }
      |> maybe_put_workitem_type_id(WorkflowConfig.request_workitem_type_id(tracker))

    with {:ok, body} <-
           Request.request("GET", "/stories", params, tracker: tracker, request_fun: request_fun),
         {:ok, issues, raw_count, page_workitem_type_ids} <-
           StoryPayload.decode("/stories", body, tracker, request_fun, validate_workitem_types?: false) do
      updated_acc = acc ++ issues

      updated_workitem_type_ids =
        WorkitemTypeScope.merge_ids(observed_workitem_type_ids, page_workitem_type_ids)

      if raw_count < @page_limit do
        with :ok <-
               WorkitemTypeScope.maybe_validate(
                 updated_workitem_type_ids,
                 tracker,
                 request_fun,
                 true
               ) do
          {:ok, updated_acc}
        end
      else
        do_fetch_stories_by_status(
          tracker,
          status_filter,
          page + 1,
          updated_acc,
          updated_workitem_type_ids,
          request_fun
        )
      end
    end
  end

  defp do_fetch_stories_by_ids(issue_ids, tracker, request_fun) do
    issue_ids
    |> Task.async_stream(
      fn issue_id ->
        fetch_story_by_id(issue_id, tracker, request_fun)
      end,
      max_concurrency: @id_fetch_max_concurrency,
      ordered: true,
      timeout: @request_timeout_ms + 1_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, issues}}, {:ok, acc} ->
        {:cont, {:ok, acc ++ issues}}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:tapd_request, reason}}}
    end)
  end

  defp maybe_put_workitem_type_id(params, workitem_type_id) do
    case Fields.normalize_string(workitem_type_id) do
      nil -> params
      value -> Map.put(params, "workitem_type_id", value)
    end
  end
end
