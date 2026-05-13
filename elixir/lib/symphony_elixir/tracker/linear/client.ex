defmodule SymphonyElixir.Tracker.Linear.Client do
  @moduledoc """
  Thin Linear GraphQL client for polling candidate issues.
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Tracker.Linear.Errors
  alias SymphonyElixir.Tracker.Linear.GraphQL
  alias SymphonyElixir.Tracker.Linear.IssueReader
  alias SymphonyElixir.Tracker.Linear.ProviderOptions
  alias SymphonyElixir.Tracker.Linear.Queries

  # ── Write Operations ─────────────────────────────────────────────

  @spec create_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(issue_id, body, opts \\ [])
      when is_binary(issue_id) and is_binary(body) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)

    with {:ok, response} <-
           graphql(
             Queries.create_comment_mutation(),
             %{issueId: issue_id, body: body},
             tracker: tracker,
             operation: :create_comment
           ),
         true <- get_in(response, ["data", "commentCreate", "success"]) == true do
      :ok
    else
      false -> {:error, Errors.normalize(:create_comment, :comment_create_failed)}
      {:error, reason} -> {:error, Errors.normalize(:create_comment, reason)}
    end
  end

  @spec update_issue_state(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name, opts \\ [])
      when is_binary(issue_id) and is_binary(state_name) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)

    with {:ok, state_id} <- resolve_state_id(tracker, issue_id, state_name),
         {:ok, response} <-
           graphql(
             Queries.update_state_mutation(),
             %{issueId: issue_id, stateId: state_id},
             tracker: tracker,
             operation: :update_issue_state
           ),
         true <- get_in(response, ["data", "issueUpdate", "success"]) == true do
      :ok
    else
      false -> {:error, Errors.normalize(:update_issue_state, :issue_update_failed)}
      {:error, reason} -> {:error, Errors.normalize(:update_issue_state, reason)}
    end
  end

  @spec healthcheck(keyword()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(opts \\ []) when is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)

    case graphql(Queries.healthcheck_query(), %{}, tracker: tracker, operation: :healthcheck) do
      {:ok, %{"data" => %{"viewer" => %{"id" => id}}}} when is_binary(id) ->
        :ok

      {:ok, _unexpected} ->
        {:error, Errors.normalize(:healthcheck, :invalid_response)}

      {:error, reason} ->
        {:error, Errors.normalize(:healthcheck, reason)}
    end
  end

  # ── Read Operations ──────────────────────────────────────────────

  @spec fetch_candidate_issues(map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(tracker) when is_map(tracker) do
    project_slug = ProviderOptions.project_slug(tracker)

    result =
      cond do
        is_nil(TrackerConfig.api_key(tracker)) ->
          {:error, :missing_linear_api_token}

        is_nil(project_slug) ->
          {:error, :missing_linear_project_slug}

        true ->
          with {:ok, assignee_filter} <- ProviderOptions.routing_assignee_filter(tracker) do
            IssueReader.fetch_by_states(
              tracker,
              project_slug,
              TrackerConfig.active_states(tracker),
              assignee_filter,
              TrackerConfig.state_phase_map(tracker)
            )
          end
      end

    map_linear_result(result, :fetch_candidate_issues)
  end

  @spec fetch_issues_by_states([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names, tracker) when is_list(state_names) and is_map(tracker) do
    normalized_states = Enum.map(state_names, &to_string/1) |> Enum.uniq()

    result =
      if normalized_states == [] do
        {:ok, []}
      else
        project_slug = ProviderOptions.project_slug(tracker)

        cond do
          is_nil(TrackerConfig.api_key(tracker)) ->
            {:error, :missing_linear_api_token}

          is_nil(project_slug) ->
            {:error, :missing_linear_project_slug}

          true ->
            IssueReader.fetch_by_states(
              tracker,
              project_slug,
              normalized_states,
              nil,
              TrackerConfig.state_phase_map(tracker)
            )
        end
      end

    map_linear_result(result, :fetch_issues_by_states)
  end

  @spec fetch_issue_states_by_ids([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, tracker) when is_list(issue_ids) and is_map(tracker) do
    ids = Enum.uniq(issue_ids)

    result =
      case ids do
        [] ->
          {:ok, []}

        ids ->
          with {:ok, assignee_filter} <- ProviderOptions.routing_assignee_filter(tracker) do
            graphql_fun = fn query, variables -> graphql(query, variables, tracker: tracker) end
            IssueReader.fetch_issue_states(ids, assignee_filter, graphql_fun, TrackerConfig.state_phase_map(tracker))
          end
      end

    map_linear_result(result, :fetch_issue_states_by_ids)
  end

  @spec graphql(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def graphql(query, variables \\ %{}, opts \\ [])
      when is_binary(query) and is_map(variables) and is_list(opts) do
    GraphQL.request(query, variables, opts)
  end

  defp map_linear_result({:error, reason}, operation), do: {:error, Errors.normalize(operation, reason)}
  defp map_linear_result(result, _operation), do: result

  defp resolve_state_id(tracker, issue_id, state_name) do
    with {:ok, response} <-
           graphql(
             Queries.state_lookup_query(),
             %{issueId: issue_id, stateName: state_name},
             tracker: tracker,
             operation: :update_issue_state
           ),
         state_id when is_binary(state_id) <-
           get_in(response, ["data", "issue", "team", "states", "nodes", Access.at(0), "id"]) do
      {:ok, state_id}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, Errors.normalize(:update_issue_state, :state_not_found)}
    end
  end
end
