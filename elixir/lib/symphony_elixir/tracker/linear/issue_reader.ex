defmodule SymphonyElixir.Tracker.Linear.IssueReader do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Linear.GraphQL
  alias SymphonyElixir.Tracker.Linear.Normalizer
  alias SymphonyElixir.Tracker.Linear.Pagination
  alias SymphonyElixir.Tracker.Linear.Queries

  @issue_page_size 50

  @spec fetch_by_states(map(), String.t(), [String.t()], map() | nil, map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_by_states(tracker, project_slug, state_names, assignee_filter, state_phase_map) do
    fetch_by_states_page(tracker, project_slug, state_names, assignee_filter, state_phase_map, nil, [])
  end

  @spec fetch_issue_states([String.t()], map() | nil, (String.t(), map() -> {:ok, map()} | {:error, term()}), map()) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states(ids, assignee_filter, graphql_fun, state_phase_map)
      when is_list(ids) and is_function(graphql_fun, 2) do
    issue_order_index = Pagination.issue_order_index(ids)
    fetch_issue_states_page(ids, assignee_filter, graphql_fun, state_phase_map, [], issue_order_index)
  end

  defp fetch_by_states_page(
         tracker,
         project_slug,
         state_names,
         assignee_filter,
         state_phase_map,
         after_cursor,
         acc_issues
       ) do
    with {:ok, body} <-
           GraphQL.request(
             Queries.poll_query(),
             %{
               projectSlug: project_slug,
               stateNames: state_names,
               first: @issue_page_size,
               relationFirst: @issue_page_size,
               after: after_cursor
             },
             tracker: tracker
           ),
         {:ok, issues, page_info} <-
           decode_page_response(body, assignee_filter, state_phase_map) do
      updated_acc = Pagination.prepend_page_issues(issues, acc_issues)

      case Pagination.next_page_cursor(page_info) do
        {:ok, next_cursor} ->
          fetch_by_states_page(
            tracker,
            project_slug,
            state_names,
            assignee_filter,
            state_phase_map,
            next_cursor,
            updated_acc
          )

        :done ->
          {:ok, Pagination.finalize_paginated_issues(updated_acc)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_issue_states_page(
         [],
         _assignee_filter,
         _graphql_fun,
         _state_phase_map,
         acc_issues,
         issue_order_index
       ) do
    acc_issues
    |> Pagination.finalize_paginated_issues()
    |> Pagination.sort_issues_by_requested_ids(issue_order_index)
    |> then(&{:ok, &1})
  end

  defp fetch_issue_states_page(
         ids,
         assignee_filter,
         graphql_fun,
         state_phase_map,
         acc_issues,
         issue_order_index
       ) do
    {batch_ids, rest_ids} = Enum.split(ids, @issue_page_size)

    case graphql_fun.(Queries.issues_by_ids_query(), %{
           ids: batch_ids,
           first: length(batch_ids),
           relationFirst: @issue_page_size
         }) do
      {:ok, body} ->
        with {:ok, issues} <- decode_response(body, assignee_filter, state_phase_map) do
          updated_acc = Pagination.prepend_page_issues(issues, acc_issues)

          fetch_issue_states_page(
            rest_ids,
            assignee_filter,
            graphql_fun,
            state_phase_map,
            updated_acc,
            issue_order_index
          )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_response(
         %{"data" => %{"issues" => %{"nodes" => nodes}}},
         assignee_filter,
         state_phase_map
       ) do
    issues =
      nodes
      |> Enum.map(&Normalizer.normalize_issue(&1, assignee_filter, state_phase_map: state_phase_map))
      |> Enum.reject(&is_nil(&1))

    {:ok, issues}
  end

  defp decode_response(%{"errors" => errors}, _assignee_filter, _state_phase_map) do
    {:error, {:linear_provider_errors, errors}}
  end

  defp decode_response(_unknown, _assignee_filter, _state_phase_map) do
    {:error, :linear_unknown_payload}
  end

  defp decode_page_response(
         %{
           "data" => %{
             "issues" => %{
               "nodes" => nodes,
               "pageInfo" => %{"hasNextPage" => has_next_page, "endCursor" => end_cursor}
             }
           }
         },
         assignee_filter,
         state_phase_map
       ) do
    with {:ok, issues} <-
           decode_response(
             %{"data" => %{"issues" => %{"nodes" => nodes}}},
             assignee_filter,
             state_phase_map
           ) do
      {:ok, issues, %{has_next_page: has_next_page == true, end_cursor: end_cursor}}
    end
  end

  defp decode_page_response(response, assignee_filter, state_phase_map),
    do: decode_response(response, assignee_filter, state_phase_map)
end
