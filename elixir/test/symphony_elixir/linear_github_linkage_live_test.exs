defmodule SymphonyElixir.LinearGitHubLinkageLiveTest do
  use ExUnit.Case, async: false

  require Logger

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Tracker.Linear.Client

  @moduletag :linear_github_linkage_live
  @moduletag timeout: 300_000

  @run_env "SYMPHONY_RUN_LINEAR_GITHUB_LINKAGE_LIVE"
  @default_team_key "TES"
  @default_change_proposal_url "https://github.com/zuoke/batt/pull/53"
  @tracker_endpoint "https://api.linear.app/graphql"

  @live_skip_reason if(System.get_env(@run_env) != "1",
                      do: "set #{@run_env}=1 to enable the real Linear/GitHub linkage live smoke"
                    )

  @team_query """
  query SymphonyLinearGitHubLinkageTeam($key: String!) {
    teams(filter: {key: {eq: $key}}, first: 1) {
      nodes {
        id
        key
        name
        states(first: 50) {
          nodes {
            id
            name
            type
          }
        }
      }
    }
  }
  """

  @create_project_mutation """
  mutation SymphonyLinearGitHubLinkageCreateProject($name: String!, $teamIds: [String!]!) {
    projectCreate(input: {name: $name, teamIds: $teamIds}) {
      success
      project {
        id
        name
        slugId
        url
      }
    }
  }
  """

  @create_issue_mutation """
  mutation SymphonyLinearGitHubLinkageCreateIssue(
    $teamId: String!
    $projectId: String!
    $title: String!
    $description: String!
    $stateId: String
  ) {
    issueCreate(
      input: {
        teamId: $teamId
        projectId: $projectId
        title: $title
        description: $description
        stateId: $stateId
      }
    ) {
      success
      issue {
        id
        identifier
        title
        description
        url
        state {
          name
        }
      }
    }
  }
  """

  @project_statuses_query """
  query SymphonyLinearGitHubLinkageProjectStatuses {
    projectStatuses(first: 50) {
      nodes {
        id
        name
        type
      }
    }
  }
  """

  @complete_project_mutation """
  mutation SymphonyLinearGitHubLinkageCompleteProject($id: String!, $statusId: String!, $completedAt: DateTime!) {
    projectUpdate(id: $id, input: {statusId: $statusId, completedAt: $completedAt}) {
      success
    }
  }
  """

  @move_issue_state_mutation """
  mutation SymphonyLinearGitHubLinkageMoveIssue($id: String!, $stateId: String!) {
    issueUpdate(id: $id, input: {stateId: $stateId}) {
      success
    }
  }
  """

  @tag skip: @live_skip_reason
  test "attaches a GitHub PR URL as an external reference through typed tracker tools" do
    api_key = required_live_env!("LINEAR_API_KEY")
    team_key = live_env("SYMPHONY_LIVE_LINEAR_TEAM_KEY", @default_team_key)
    change_proposal_url = live_env("SYMPHONY_LINEAR_LINKAGE_PR_URL", @default_change_proposal_url)
    tracker = linear_tracker(api_key)

    team = fetch_team!(tracker, team_key)
    initial_state = initial_state!(team)
    terminal_state = terminal_state!(team)
    completed_project_status = completed_project_status!(tracker)
    run_id = "symphony-linear-github-linkage-#{System.system_time(:second)}"
    project = create_project!(tracker, team["id"], run_id)
    issue = create_issue!(tracker, team["id"], project["id"], initial_state["id"], run_id)

    try do
      context = tracker_tool_context(tracker)

      attached =
        execute_success!(
          context,
          "linear_attach_external_reference",
          %{
            "issue_id" => issue["id"],
            "url" => change_proposal_url,
            "title" => "Symphony GitHub linkage live probe",
            "reference_kind" => "change_proposal",
            "provider_kind" => "github",
            "external_id" => github_pr_number(change_proposal_url),
            "metadata" => %{"repository" => github_repository(change_proposal_url)}
          }
        )

      assert get_in(attached, ["data", "attachment", "url"]) == change_proposal_url

      snapshot =
        execute_success!(
          context,
          "linear_issue_snapshot",
          %{
            "issue_id" => issue["id"],
            "include_attachments" => true,
            "include_comments" => false
          }
        )

      attachments = get_in(snapshot, ["data", "issue", "attachments"]) || []
      assert Enum.any?(attachments, &(Map.get(&1, "url") == change_proposal_url))

      IO.puts(
        "linear_github_linkage_live_probe " <>
          "identifier=#{issue["identifier"]} change_proposal=#{redacted_change_proposal(change_proposal_url)}"
      )
    after
      move_issue_to_state(tracker, issue["id"], terminal_state["id"])
      complete_project(tracker, project["id"], completed_project_status["id"])
    end
  end

  defp tracker_tool_context(tracker) do
    DynamicTool.capture_context(dynamic_tool_sources: [{SymphonyElixir.Tracker.DynamicToolSource, tracker}])
  end

  defp execute_success!(context, tool, arguments) do
    case DynamicTool.execute(context, tool, arguments) do
      {:success, payload} ->
        payload

      {:failure, payload} ->
        flunk("#{tool} failed: #{inspect(payload)}")

      {:error, reason} ->
        flunk("#{tool} errored: #{inspect(reason)}")
    end
  end

  defp fetch_team!(tracker, team_key) do
    @team_query
    |> graphql_data!(tracker, %{key: team_key})
    |> get_in(["teams", "nodes"])
    |> case do
      [team | _] ->
        team

      _other ->
        flunk("expected Linear team #{inspect(team_key)} to exist")
    end
  end

  defp initial_state!(%{"states" => %{"nodes" => states}}) when is_list(states) do
    Enum.find(states, &(&1["type"] == "unstarted")) ||
      Enum.find(states, &(&1["type"] == "started")) ||
      Enum.find(states, &(&1["type"] not in ["completed", "canceled"])) ||
      flunk("expected team to expose at least one non-terminal workflow state")
  end

  defp terminal_state!(%{"states" => %{"nodes" => states}}) when is_list(states) do
    Enum.find(states, &(&1["name"] == "Done")) ||
      Enum.find(states, &(&1["type"] == "completed")) ||
      Enum.find(states, &(&1["type"] == "canceled")) ||
      flunk("expected team to expose at least one terminal workflow state")
  end

  defp completed_project_status!(tracker) do
    @project_statuses_query
    |> graphql_data!(tracker, %{})
    |> get_in(["projectStatuses", "nodes"])
    |> case do
      statuses when is_list(statuses) ->
        Enum.find(statuses, &(&1["type"] == "completed")) ||
          flunk("expected workspace to expose a completed project status")

      payload ->
        flunk("expected project statuses list, got: #{inspect(payload)}")
    end
  end

  defp create_project!(tracker, team_id, name) do
    @create_project_mutation
    |> graphql_data!(tracker, %{teamIds: [team_id], name: name})
    |> fetch_successful_entity!("projectCreate", "project")
  end

  defp create_issue!(tracker, team_id, project_id, state_id, title) do
    @create_issue_mutation
    |> graphql_data!(tracker, %{
      teamId: team_id,
      projectId: project_id,
      title: title,
      description: title,
      stateId: state_id
    })
    |> fetch_successful_entity!("issueCreate", "issue")
  end

  defp complete_project(tracker, project_id, completed_status_id)
       when is_binary(project_id) and is_binary(completed_status_id) do
    update_entity(
      tracker,
      @complete_project_mutation,
      %{
        id: project_id,
        statusId: completed_status_id,
        completedAt: DateTime.utc_now(:second) |> DateTime.to_iso8601()
      },
      "projectUpdate",
      "project"
    )
  end

  defp move_issue_to_state(tracker, issue_id, state_id)
       when is_binary(issue_id) and is_binary(state_id) do
    update_entity(
      tracker,
      @move_issue_state_mutation,
      %{id: issue_id, stateId: state_id},
      "issueUpdate",
      "issue"
    )
  end

  defp update_entity(tracker, mutation, variables, mutation_name, entity_name) do
    case Client.graphql(mutation, variables, tracker: tracker) do
      {:ok, %{"data" => %{^mutation_name => %{"success" => true}}}} ->
        :ok

      {:ok, %{"errors" => errors}} ->
        Logger.warning("Linear/GitHub linkage live finalization failed for #{entity_name}: #{inspect(errors)}")
        :ok

      {:ok, payload} ->
        Logger.warning("Linear/GitHub linkage live finalization failed for #{entity_name}: #{inspect(payload)}")
        :ok

      {:error, reason} ->
        Logger.warning("Linear/GitHub linkage live finalization failed for #{entity_name}: #{inspect(reason)}")
        :ok
    end
  end

  defp graphql_data!(query, tracker, variables) when is_binary(query) and is_map(variables) do
    case Client.graphql(query, variables, tracker: tracker) do
      {:ok, %{"data" => data, "errors" => errors}} when is_map(data) and is_list(errors) ->
        flunk("Linear GraphQL returned partial errors: #{inspect(errors)}")

      {:ok, %{"errors" => errors}} when is_list(errors) ->
        flunk("Linear GraphQL failed: #{inspect(errors)}")

      {:ok, %{"data" => data}} when is_map(data) ->
        data

      {:ok, payload} ->
        flunk("Linear GraphQL returned unexpected payload: #{inspect(payload)}")

      {:error, reason} ->
        flunk("Linear GraphQL request failed: #{inspect(reason)}")
    end
  end

  defp fetch_successful_entity!(data, mutation_name, entity_name)
       when is_map(data) and is_binary(mutation_name) and is_binary(entity_name) do
    case data do
      %{^mutation_name => %{"success" => true, ^entity_name => %{} = entity}} ->
        entity

      _other ->
        flunk("expected successful #{mutation_name} response, got: #{inspect(data)}")
    end
  end

  defp linear_tracker(api_key) do
    %{
      kind: "linear",
      endpoint: @tracker_endpoint,
      auth: %{api_key: api_key},
      provider: %{}
    }
  end

  defp required_live_env!(key) do
    case System.get_env(key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> flunk("set #{key} to run this live smoke")
          trimmed -> trimmed
        end

      _value ->
        flunk("set #{key} to run this live smoke")
    end
  end

  defp live_env(key, default) do
    case System.get_env(key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> default
          trimmed -> trimmed
        end

      _value ->
        default
    end
  end

  defp github_repository(url) when is_binary(url) do
    case Regex.run(~r{github\.com/([^/]+/[^/]+)/pull/\d+}, url, capture: :all_but_first) do
      [repository] -> repository
      _other -> nil
    end
  end

  defp github_pr_number(url) when is_binary(url) do
    case Regex.run(~r{/pull/(\d+)}, url, capture: :all_but_first) do
      [number] -> number
      _other -> nil
    end
  end

  defp redacted_change_proposal(url) when is_binary(url) do
    case {github_repository(url), github_pr_number(url)} do
      {repository, number} when is_binary(repository) and is_binary(number) -> "#{repository}##{number}"
      _other -> "configured"
    end
  end
end
