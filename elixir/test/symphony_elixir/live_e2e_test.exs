defmodule SymphonyElixir.LiveE2ETest do
  use SymphonyElixir.TestSupport

  require Logger
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Platform.SSH

  @moduletag :live_e2e
  # Keep the ExUnit envelope longer than the provider turn/stall timeout so
  # live failures can unwind through normal cleanup instead of killing the test.
  @moduletag timeout: 900_000

  @default_team_key "SYME2E"
  @default_docker_auth_json Path.join(System.user_home!(), ".codex/auth.json")
  @docker_worker_count 2
  @docker_support_dir Path.expand("../support/live_e2e_docker", __DIR__)
  @docker_compose_file Path.join(@docker_support_dir, "docker-compose.yml")
  @result_file "LIVE_E2E_RESULT.txt"
  @joined_live_env "SYMPHONY_RUN_FULL_CODING_PR_DELIVERY_LIVE"
  @default_repository "acme/widgets"
  @default_base_branch "master"
  @default_branch_prefix "symphony/live"
  @live_e2e_skip_reason if(System.get_env("SYMPHONY_RUN_LIVE_E2E") != "1",
                          do: "set SYMPHONY_RUN_LIVE_E2E=1 to enable the real Linear/Codex end-to-end test"
                        )

  @joined_live_skip_reason if(System.get_env(@joined_live_env) != "1",
                             do: "set #{@joined_live_env}=1 to enable the real Linear/GitHub/Codex joined live smoke"
                           )

  @team_query """
  query SymphonyLiveE2ETeam($key: String!) {
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
  mutation SymphonyLiveE2ECreateProject($name: String!, $teamIds: [String!]!) {
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
  mutation SymphonyLiveE2ECreateIssue(
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
  query SymphonyLiveE2EProjectStatuses {
    projectStatuses(first: 50) {
      nodes {
        id
        name
        type
      }
    }
  }
  """

  @issue_details_query """
  query SymphonyLiveE2EIssueDetails($id: String!) {
    issue(id: $id) {
      id
      identifier
      state {
        name
        type
      }
      attachments {
        nodes {
          title
          url
        }
      }
      comments(first: 20) {
        nodes {
          body
        }
      }
    }
  }
  """

  @complete_project_mutation """
  mutation SymphonyLiveE2ECompleteProject($id: String!, $statusId: String!, $completedAt: DateTime!) {
    projectUpdate(id: $id, input: {statusId: $statusId, completedAt: $completedAt}) {
      success
    }
  }
  """

  @move_issue_state_mutation """
  mutation SymphonyLiveE2EMoveIssue($id: String!, $stateId: String!) {
    issueUpdate(id: $id, input: {stateId: $stateId}) {
      success
    }
  }
  """

  @tag skip: @live_e2e_skip_reason
  @tag timeout: 240_000
  test "calls a real Linear snapshot through a local Codex MCP turn" do
    run_live_issue_flow!(:local, :snapshot_probe)
  end

  @tag skip: @live_e2e_skip_reason
  test "creates a real Linear project and issue with a local worker" do
    run_live_issue_flow!(:local)
  end

  @tag skip: @joined_live_skip_reason
  test "creates and links a GitHub change proposal through a local Codex turn" do
    run_live_issue_flow!(:local, :joined_coding_pr_delivery)
  end

  @tag skip: @live_e2e_skip_reason
  test "creates a real Linear project and issue with an ssh worker" do
    run_live_issue_flow!(:ssh)
  end

  defp fetch_team!(team_key) do
    @team_query
    |> graphql_data!(%{key: team_key})
    |> get_in(["teams", "nodes"])
    |> case do
      [team | _] ->
        team

      _ ->
        flunk("expected Linear team #{inspect(team_key)} to exist")
    end
  end

  defp active_state!(%{"states" => %{"nodes" => states}}) when is_list(states) do
    Enum.find(states, &(&1["type"] == "started")) ||
      Enum.find(states, &(&1["type"] == "unstarted")) ||
      Enum.find(states, &(&1["type"] not in ["completed", "canceled"])) ||
      flunk("expected team to expose at least one non-terminal workflow state")
  end

  defp initial_state!(team, review_state) do
    review_state_id = review_state["id"]
    states = get_in(team, ["states", "nodes"]) || []

    Enum.find(states, &(&1["type"] == "unstarted" and &1["id"] != review_state_id)) ||
      Enum.find(states, &(&1["type"] == "started" and &1["id"] != review_state_id)) ||
      Enum.find(states, &(&1["type"] not in ["completed", "canceled"] and &1["id"] != review_state_id)) ||
      active_state!(team)
  end

  defp review_state!(%{"states" => %{"nodes" => states}}) when is_list(states) do
    Enum.find(states, &(&1["name"] == "In Review")) ||
      Enum.find(states, &(normalized_state_name(&1) in ["review", "in review", "ready for review"])) ||
      flunk("expected Linear team to expose an In Review or review-equivalent workflow state")
  end

  defp terminal_state!(%{"states" => %{"nodes" => states}}) when is_list(states) do
    Enum.find(states, &(&1["name"] == "Done")) ||
      Enum.find(states, &(&1["type"] == "completed")) ||
      Enum.find(states, &(&1["type"] == "canceled")) ||
      flunk("expected team to expose at least one terminal workflow state")
  end

  defp terminal_state_names(%{"states" => %{"nodes" => states}}) when is_list(states) do
    states
    |> Enum.filter(&(&1["type"] in ["completed", "canceled"]))
    |> Enum.map(& &1["name"])
    |> case do
      [] -> ["Done", "Canceled", "Cancelled"]
      names -> names
    end
  end

  defp active_state_names(%{"states" => %{"nodes" => states}}) when is_list(states) do
    states
    |> Enum.reject(&(&1["type"] in ["completed", "canceled"]))
    |> Enum.map(& &1["name"])
    |> case do
      [] -> ["Todo", "In Progress", "In Review"]
      names -> names
    end
  end

  defp completed_project_status! do
    @project_statuses_query
    |> graphql_data!(%{})
    |> get_in(["projectStatuses", "nodes"])
    |> case do
      statuses when is_list(statuses) ->
        Enum.find(statuses, &(&1["type"] == "completed")) ||
          flunk("expected workspace to expose a completed project status")

      payload ->
        flunk("expected project statuses list, got: #{inspect(payload)}")
    end
  end

  defp create_project!(team_id, name) do
    @create_project_mutation
    |> graphql_data!(%{teamIds: [team_id], name: name})
    |> fetch_successful_entity!("projectCreate", "project")
  end

  defp create_issue!(team_id, project_id, state_id, title) do
    issue =
      @create_issue_mutation
      |> graphql_data!(%{
        teamId: team_id,
        projectId: project_id,
        title: title,
        description: title,
        stateId: state_id
      })
      |> fetch_successful_entity!("issueCreate", "issue")

    %Issue{
      id: issue["id"],
      identifier: issue["identifier"],
      title: issue["title"],
      description: issue["description"],
      state: get_in(issue, ["state", "name"]),
      url: issue["url"],
      labels: [],
      blocked_by: []
    }
  end

  defp complete_project(project_id, completed_status_id)
       when is_binary(project_id) and is_binary(completed_status_id) do
    update_entity(
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

  defp move_issue_to_state(issue_id, state_id)
       when is_binary(issue_id) and is_binary(state_id) do
    update_entity(
      @move_issue_state_mutation,
      %{id: issue_id, stateId: state_id},
      "issueUpdate",
      "issue"
    )
  end

  defp fetch_issue_details!(issue_id) when is_binary(issue_id) do
    @issue_details_query
    |> graphql_data!(%{id: issue_id})
    |> get_in(["issue"])
    |> case do
      %{} = issue -> issue
      payload -> flunk("expected issue details payload, got: #{inspect(payload)}")
    end
  end

  defp issue_in_review?(%{"state" => %{"name" => name, "type" => type}}, expected_state_name) do
    name == expected_state_name and type not in ["completed", "canceled"]
  end

  defp issue_in_review?(_issue, _expected_state_name), do: false

  defp normalized_state_name(%{"name" => name}), do: String.downcase(to_string(name))
  defp normalized_state_name(_state), do: ""

  defp issue_has_comment?(%{"comments" => %{"nodes" => comments}}, expected_body) when is_list(comments) do
    Enum.any?(comments, fn comment ->
      comment
      |> Map.get("body", "")
      |> String.contains?(expected_body)
    end)
  end

  defp issue_has_comment?(_issue, _expected_body), do: false

  defp issue_has_attachment?(%{"attachments" => %{"nodes" => attachments}}, expected_url)
       when is_list(attachments) and is_binary(expected_url) do
    Enum.any?(attachments, &(Map.get(&1, "url") == expected_url))
  end

  defp issue_has_attachment?(_issue, _expected_url), do: false

  defp update_entity(mutation, variables, mutation_name, entity_name) do
    case Client.graphql(mutation, variables, tracker: SymphonyElixir.Config.settings!().tracker) do
      {:ok, %{"data" => %{^mutation_name => %{"success" => true}}}} ->
        :ok

      {:ok, %{"errors" => errors}} ->
        Logger.warning("Live e2e finalization failed for #{entity_name}: #{inspect(errors)}")
        :ok

      {:ok, payload} ->
        Logger.warning("Live e2e finalization failed for #{entity_name}: #{inspect(payload)}")
        :ok

      {:error, reason} ->
        Logger.warning("Live e2e finalization failed for #{entity_name}: #{inspect(reason)}")
        :ok
    end
  end

  defp graphql_data!(query, variables) when is_binary(query) and is_map(variables) do
    case Client.graphql(query, variables, tracker: SymphonyElixir.Config.settings!().tracker) do
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

      _ ->
        flunk("expected successful #{mutation_name} response, got: #{inspect(data)}")
    end
  end

  defp live_prompt(project_slug, review_state_name) do
    """
    You are running a real Symphony end-to-end test.

    The current working directory is the workspace root.

    Generated tool inventory for this session:

    {{ runtime.tool_inventory }}

    For every routine Linear action listed in the inventory, call the exact
    provider-facing callable tool name shown in the inventory. Runtime tool
    names identify the intended Symphony tool, but Codex must call the
    corresponding `mcp__symphony-planned-tools__...` callable from the
    inventory. For this smoke, that means:
    - `mcp__symphony-planned-tools__linear_issue_snapshot`
    - `mcp__symphony-planned-tools__linear_upsert_workpad`
    - `mcp__symphony-planned-tools__linear_move_issue`

    Do not replace these typed capabilities with raw Linear GraphQL operations,
    helper CLIs, shell commands, or alternate provider APIs.

    Step 1:
    Call inventory capability `tracker.issue_snapshot` / runtime tool
    `linear_issue_snapshot` through provider-facing callable
    `mcp__symphony-planned-tools__linear_issue_snapshot` with:
    - `issue_id`: `{{ issue.id }}`
    - `include_comments`: true

    Read the existing comments and team workflow states.

    Step 2:
    If the workpad/comment body below is not already present, call inventory
    capability `tracker.upsert_workpad` / runtime tool `linear_upsert_workpad`
    through provider-facing callable
    `mcp__symphony-planned-tools__linear_upsert_workpad` with:
    - `issue_id`: `{{ issue.id }}`
    - `heading`: `Symphony Live E2E Workpad`
    - `body`: the exact body below

    #{expected_comment("{{ issue.identifier }}", project_slug)}

    Step 3:
    Call inventory capability `tracker.move_issue` / runtime tool
    `linear_move_issue` through provider-facing callable
    `mcp__symphony-planned-tools__linear_move_issue` with:
    - `issue_id`: `{{ issue.id }}`
    - `state_name`: `#{review_state_name}`

    Step 4:
    Verify all Linear outcomes with one final call through provider-facing
    callable `mcp__symphony-planned-tools__linear_issue_snapshot` against
    `{{ issue.id }}`:
    - the workpad/comment body contains the exact body above
    - the issue state name is exactly `#{review_state_name}`

    Step 5:
    Create a file named #{@result_file} in the current working directory by running exactly:

    ```sh
    cat > #{@result_file} <<'EOF'
    identifier={{ issue.identifier }}
    project_slug=#{project_slug}
    EOF
    ```

    Then verify it by running:

    ```sh
    cat #{@result_file}
    ```

    The file content must be exactly:
    identifier={{ issue.identifier }}
    project_slug=#{project_slug}

    Do not ask for approval.
    Do not move the issue to a terminal state; the test harness finalizes the
    temporary issue after it verifies the handoff state.
    Stop only after all three conditions are true:
    1. the Linear workpad/comment contains the exact body above
    2. the Linear issue is in `#{review_state_name}` for human review handoff
    3. the file exists with the exact contents above
    """
  end

  defp live_snapshot_prompt do
    """
    You are running a narrow Symphony live MCP snapshot probe.

    The current working directory is the workspace root.

    Generated tool inventory for this session:

    {{ runtime.tool_inventory }}

    Call exactly one tool, then stop:
    `mcp__symphony-planned-tools__linear_issue_snapshot`

    Use these arguments:
    - `issue_id`: `{{ issue.id }}`
    - `include_comments`: true

    Do not write files, run shell commands, inspect the repository, move the
    issue, update comments, call raw Linear GraphQL, or ask for approval.
    """
  end

  defp live_joined_coding_prompt(project_slug, review_state_name, repo_live) when is_map(repo_live) do
    probe_file = ".symphony-live-smoke/#{safe_file_name(repo_live.branch)}.txt"

    """
    You are running a real Symphony joined coding PR delivery live smoke.

    The current working directory is the workspace root. The target repository
    is already cloned at `repo/`.

    Generated tool inventory for this session:

    {{ runtime.tool_inventory }}

    For every routine Linear, repo-core, and repo-provider action listed in the
    inventory, call the exact provider-facing callable tool name shown in the
    inventory. Runtime tool names identify the intended Symphony tool, but
    Codex must call the corresponding
    `mcp__symphony-planned-tools__...` callable from the inventory.

    For this smoke, use these provider-facing callable tools:
    - `mcp__symphony-planned-tools__linear_issue_snapshot`
    - `mcp__symphony-planned-tools__linear_upsert_workpad`
    - `mcp__symphony-planned-tools__repo_checkout`
    - `mcp__symphony-planned-tools__repo_diff`
    - `mcp__symphony-planned-tools__repo_commit`
    - `mcp__symphony-planned-tools__repo_push`
    - `mcp__symphony-planned-tools__repo_create_or_update_change_proposal`
    - `mcp__symphony-planned-tools__repo_change_proposal_snapshot`
    - `mcp__symphony-planned-tools__repo_read_change_proposal_checks`
    - `mcp__symphony-planned-tools__linear_attach_change_proposal`
    - `mcp__symphony-planned-tools__linear_move_issue`

    Do not replace these typed capabilities with raw Linear GraphQL operations,
    GitHub CLI commands, git commit/push commands, shell git side effects, or
    alternate provider APIs. Shell is allowed only for creating and reading the
    small probe file inside `repo/`.

    Step 1:
    Call `mcp__symphony-planned-tools__linear_issue_snapshot` with:
    - `issue_id`: `{{ issue.id }}`
    - `include_comments`: true
    - `include_attachments`: true

    Step 2:
    Call `mcp__symphony-planned-tools__linear_upsert_workpad` with:
    - `issue_id`: `{{ issue.id }}`
    - `heading`: `Symphony Live E2E Workpad`
    - `body`: the exact body below

    #{expected_comment("{{ issue.identifier }}", project_slug)}

    Step 3:
    Call `mcp__symphony-planned-tools__repo_checkout` with:
    - `branch`: `#{repo_live.branch}`
    - `base`: `origin/#{repo_live.base_branch}`
    - `mode`: `create`

    Step 4:
    Create the probe file inside the repository by running exactly:

    ```sh
    mkdir -p repo/.symphony-live-smoke
    cat > repo/#{probe_file} <<'EOF'
    identifier={{ issue.identifier }}
    project_slug=#{project_slug}
    branch=#{repo_live.branch}
    EOF
    cat repo/#{probe_file}
    ```

    Step 5:
    Call `mcp__symphony-planned-tools__repo_diff` with:
    - `check`: true

    Step 6:
    Call `mcp__symphony-planned-tools__repo_commit` with:
    - `message`: `chore: add joined coding PR live probe`
    - `mode`: `all`

    Step 7:
    Call `mcp__symphony-planned-tools__repo_push` with:
    - `branch`: `#{repo_live.branch}`
    - `set_upstream`: true
    - `verify`: true

    Step 8:
    Call `mcp__symphony-planned-tools__repo_create_or_update_change_proposal`
    with:
    - `mode`: `create`
    - `title`: `Symphony joined coding PR live probe`
    - `body`: `Temporary PR created by Symphony's joined coding PR delivery live smoke.`
    - `base`: `#{repo_live.base_branch}`
    - `head`: `#{repo_live.branch}`

    Save the returned change proposal URL and number.

    Step 9:
    Call `mcp__symphony-planned-tools__repo_change_proposal_snapshot` with:
    - `number`: the change proposal number returned in Step 8
    - `include_discussion`: false
    - `include_checks`: false

    Verify the snapshot head branch is `#{repo_live.branch}`.

    Step 10:
    Call `mcp__symphony-planned-tools__repo_read_change_proposal_checks` with:
    - `number`: the change proposal number returned in Step 8

    Record whether checks are present or unavailable in the workpad.

    Step 11:
    Call `mcp__symphony-planned-tools__linear_attach_change_proposal` with:
    - `issue_id`: `{{ issue.id }}`
    - `url`: the change proposal URL returned in Step 8
    - `title`: `Symphony joined coding PR live probe`
    - `repo_provider_kind`: `github`
    - `repository`: `#{repo_live.repository}`
    - `change_proposal_id`: the change proposal number returned in Step 8

    Step 12:
    Call `mcp__symphony-planned-tools__linear_move_issue` with:
    - `issue_id`: `{{ issue.id }}`
    - `state_name`: `#{review_state_name}`

    Step 13:
    Verify final tracker state with
    `mcp__symphony-planned-tools__linear_issue_snapshot` against
    `{{ issue.id }}` using:
    - `include_comments`: true
    - `include_attachments`: true

    Step 14:
    Create a file named #{@result_file} in the workspace root by running exactly:

    ```sh
    cat > #{@result_file} <<'EOF'
    identifier={{ issue.identifier }}
    project_slug=#{project_slug}
    branch=#{repo_live.branch}
    EOF
    cat #{@result_file}
    ```

    Stop only after all conditions are true:
    1. the workpad/comment contains the exact body above
    2. the repository branch `#{repo_live.branch}` has been pushed
    3. a GitHub change proposal exists for `#{repo_live.branch}`
    4. GitHub change proposal checks were read through the typed tool
    5. the Linear issue attachment points to that change proposal URL
    6. the Linear issue is in `#{review_state_name}` for human review handoff
    7. #{@result_file} exists with the exact contents from Step 14

    Do not ask for approval. Do not close the PR, delete the remote branch, or
    move the issue to a terminal state; the test harness performs cleanup after
    verification.
    """
  end

  defp live_prompt_for(:snapshot_probe, _project_slug, _review_state_name, _repo_live), do: live_snapshot_prompt()
  defp live_prompt_for(:full, project_slug, review_state_name, _repo_live), do: live_prompt(project_slug, review_state_name)

  defp live_prompt_for(:joined_coding_pr_delivery, project_slug, review_state_name, repo_live),
    do: live_joined_coding_prompt(project_slug, review_state_name, repo_live)

  defp live_turn_timeout_ms(:snapshot_probe), do: 120_000
  defp live_turn_timeout_ms(:joined_coding_pr_delivery), do: 840_000
  defp live_turn_timeout_ms(:full), do: 600_000

  defp expected_result(issue_identifier, project_slug) do
    "identifier=#{issue_identifier}\nproject_slug=#{project_slug}\n"
  end

  defp expected_comment(issue_identifier, project_slug) do
    "Symphony live e2e comment\nidentifier=#{issue_identifier}\nproject_slug=#{project_slug}"
  end

  defp expected_joined_result(issue_identifier, project_slug, branch) do
    "identifier=#{issue_identifier}\nproject_slug=#{project_slug}\nbranch=#{branch}\n"
  end

  defp receive_runtime_info!(issue_id) do
    receive do
      {:worker_runtime_info, ^issue_id, %{workspace_path: workspace_path} = runtime_info}
      when is_binary(workspace_path) ->
        runtime_info

      {:agent_worker_update, ^issue_id, _message} ->
        receive_runtime_info!(issue_id)
    after
      5_000 ->
        flunk("timed out waiting for worker runtime info for #{inspect(issue_id)}")
    end
  end

  defp assert_dynamic_tool_succeeded!(runtime_info, tool, timeout_ms \\ 60_000)
       when is_map(runtime_info) and is_binary(tool) and is_integer(timeout_ms) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    assert_dynamic_tool_succeeded_until!(runtime_info, tool, deadline_ms)
  end

  defp assert_dynamic_tool_succeeded_until!(runtime_info, tool, deadline_ms)
       when is_map(runtime_info) and is_binary(tool) and is_integer(deadline_ms) do
    events = dynamic_tool_events(runtime_info)

    if Enum.any?(events, &typed_tool_success?(&1, tool)) do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline_ms do
        Process.sleep(100)
        assert_dynamic_tool_succeeded_until!(runtime_info, tool, deadline_ms)
      else
        flunk("expected typed #{tool} success in #{inspect(dynamic_tool_event_summary(events))}")
      end
    end
  end

  defp typed_tool_success?(event, tool) when is_map(event) and is_binary(tool) do
    event["event"] == "tool_call_succeeded" and
      event["tool_name"] == tool and
      event["dynamic_tool_usage_kind"] == "typed"
  end

  defp dynamic_tool_events(runtime_info) when is_map(runtime_info) do
    runtime_info
    |> Map.take([:run_id, :issue_id, :issue_identifier])
    |> EventStore.recent_issue_events(limit: 1_000)
    |> Enum.filter(fn event ->
      event_name = Map.get(event, "event")
      is_binary(event_name) and String.starts_with?(event_name, "tool_call_")
    end)
  end

  defp dynamic_tool_event_summary(events) when is_list(events) do
    Enum.map(events, fn event ->
      Map.take(event, [
        "event",
        "tool_name",
        "dynamic_tool_usage_kind",
        "dynamic_tool_failure_reason",
        "dynamic_tool_exposure"
      ])
    end)
  end

  defp read_worker_result!(%{worker_host: nil, workspace_path: workspace_path}, result_file)
       when is_binary(workspace_path) and is_binary(result_file) do
    File.read!(Path.join(workspace_path, result_file))
  end

  defp read_worker_result!(%{worker_host: worker_host, workspace_path: workspace_path}, result_file)
       when is_binary(worker_host) and is_binary(workspace_path) and is_binary(result_file) do
    remote_result_path = Path.join(workspace_path, result_file)

    case SSH.run(worker_host, "cat #{shell_escape(remote_result_path)}", stderr_to_stdout: true) do
      {:ok, {output, 0}} ->
        output

      {:ok, {output, status}} ->
        flunk("failed to read remote result from #{worker_host}:#{remote_result_path} (status #{status}): #{inspect(output)}")

      {:error, reason} ->
        flunk("failed to read remote result from #{worker_host}:#{remote_result_path}: #{inspect(reason)}")
    end
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp run_live_issue_flow!(backend), do: run_live_issue_flow!(backend, :full)

  defp run_live_issue_flow!(backend, mode)
       when backend in [:local, :ssh] and mode in [:full, :snapshot_probe, :joined_coding_pr_delivery] do
    run_id = "symphony-live-e2e-#{backend}-#{System.unique_integer([:positive])}"
    test_root = Path.join(System.tmp_dir!(), run_id)
    workflow_root = Path.join(test_root, "workflow")
    workflow_file = Path.join(workflow_root, "WORKFLOW.md")
    worker_setup = live_worker_setup!(backend, run_id, test_root)
    repo_live = live_repo_config(mode)
    team_key = System.get_env("SYMPHONY_LIVE_LINEAR_TEAM_KEY") || @default_team_key
    original_workflow_path = Workflow.workflow_file_path()
    orchestrator_pid = Process.whereis(SymphonyElixir.Orchestrator)

    File.mkdir_p!(workflow_root)

    try do
      if is_pid(orchestrator_pid) do
        assert :ok = terminate_supervised_child(SymphonyElixir.Orchestrator)
      end

      Workflow.set_workflow_file_path(workflow_file)

      write_workflow_file!(
        workflow_file,
        [
          workflow_profile_options: live_workflow_profile_options(mode),
          tracker_api_token: "$LINEAR_API_KEY",
          tracker_project_slug: "bootstrap",
          workspace_root: worker_setup.workspace_root,
          worker_ssh_hosts: worker_setup.ssh_worker_hosts,
          agent_provider_options: Map.merge(worker_setup.agent_provider_options, %{approval_policy: "never"}),
          observability_enabled: false,
          observability_global_event_limit: 10_000,
          observability_issue_event_limit: 2_000,
          observability_run_event_limit: 2_000,
          observability_session_event_limit: 2_000,
          observability_pending_event_queue_limit: 20_000
        ] ++ live_repo_workflow_options(repo_live)
      )

      team = fetch_team!(team_key)
      review_state = review_state!(team)
      active_state = initial_state!(team, review_state)
      terminal_state = terminal_state!(team)
      completed_project_status = completed_project_status!()
      terminal_states = terminal_state_names(team)

      project =
        create_project!(
          team["id"],
          "Symphony Live E2E #{backend} #{System.unique_integer([:positive])}"
        )

      issue =
        create_issue!(
          team["id"],
          project["id"],
          active_state["id"],
          "Symphony live e2e #{backend} issue for #{project["name"]}"
        )

      try do
        write_workflow_file!(
          workflow_file,
          [
            workflow_profile_options: live_workflow_profile_options(mode),
            tracker_api_token: "$LINEAR_API_KEY",
            tracker_project_slug: project["slugId"],
            tracker_active_states: active_state_names(team),
            tracker_terminal_states: terminal_states,
            workspace_root: worker_setup.workspace_root,
            worker_ssh_hosts: worker_setup.ssh_worker_hosts,
            server_port: 0,
            agent_provider_options:
              Map.merge(worker_setup.agent_provider_options, %{
                approval_policy: "never",
                turn_timeout_ms: live_turn_timeout_ms(mode),
                stall_timeout_ms: live_turn_timeout_ms(mode)
              }),
            observability_enabled: false,
            observability_global_event_limit: 10_000,
            observability_issue_event_limit: 2_000,
            observability_run_event_limit: 2_000,
            observability_session_event_limit: 2_000,
            observability_pending_event_queue_limit: 20_000,
            prompt: live_prompt_for(mode, project["slugId"], review_state["name"], repo_live)
          ] ++ live_repo_workflow_options(repo_live)
        )

        assert :ok = restart_supervised_child(SymphonyElixir.HttpServer)
        assert is_integer(SymphonyElixir.HttpServer.bound_port())

        # This smoke proves the planned typed-tool path in one turn. The target
        # handoff state is intentionally active, so allowing continuation would
        # make the generic runner ask for more work and could overwrite the
        # review handoff before assertions run.
        assert :ok = AgentRunner.run(issue, self(), max_turns: 1)

        runtime_info =
          issue.id
          |> receive_runtime_info!()
          |> Map.merge(%{issue_id: issue.id, issue_identifier: issue.identifier})

        assert_dynamic_tool_succeeded!(runtime_info, "linear_issue_snapshot")

        if mode == :full do
          assert_dynamic_tool_succeeded!(runtime_info, "linear_upsert_workpad")
          assert_dynamic_tool_succeeded!(runtime_info, "linear_move_issue")

          assert read_worker_result!(runtime_info, @result_file) ==
                   expected_result(issue.identifier, project["slugId"])

          issue_snapshot = fetch_issue_details!(issue.id)
          assert issue_in_review?(issue_snapshot, review_state["name"])
          assert issue_has_comment?(issue_snapshot, expected_comment(issue.identifier, project["slugId"]))
        end

        if mode == :joined_coding_pr_delivery do
          assert_dynamic_tool_succeeded!(runtime_info, "linear_upsert_workpad")
          assert_dynamic_tool_succeeded!(runtime_info, "repo_checkout")
          assert_dynamic_tool_succeeded!(runtime_info, "repo_diff")
          assert_dynamic_tool_succeeded!(runtime_info, "repo_commit")
          assert_dynamic_tool_succeeded!(runtime_info, "repo_push")
          assert_dynamic_tool_succeeded!(runtime_info, "repo_create_or_update_change_proposal")
          assert_dynamic_tool_succeeded!(runtime_info, "repo_change_proposal_snapshot")
          assert_dynamic_tool_succeeded!(runtime_info, "repo_read_change_proposal_checks")
          assert_dynamic_tool_succeeded!(runtime_info, "linear_attach_change_proposal")
          assert_dynamic_tool_succeeded!(runtime_info, "linear_move_issue")

          assert read_worker_result!(runtime_info, @result_file) ==
                   expected_joined_result(issue.identifier, project["slugId"], repo_live.branch)

          change_proposal = fetch_open_change_proposal_for_branch!(repo_live.repository, repo_live.branch)
          issue_snapshot = fetch_issue_details!(issue.id)
          assert issue_in_review?(issue_snapshot, review_state["name"])
          assert issue_has_comment?(issue_snapshot, expected_comment(issue.identifier, project["slugId"]))
          assert issue_has_attachment?(issue_snapshot, change_proposal.url)
        end
      after
        cleanup_live_repo(repo_live)
        move_issue_to_state(issue.id, terminal_state["id"])
        complete_project(project["id"], completed_project_status["id"])
      end
    after
      restart_orchestrator_if_needed()
      cleanup_live_worker_setup(worker_setup)
      Workflow.set_workflow_file_path(original_workflow_path)
      File.rm_rf(test_root)
    end
  end

  defp live_worker_setup!(:local, _run_id, test_root) when is_binary(test_root) do
    %{
      cleanup: fn -> :ok end,
      agent_provider_options: %{command: "codex app-server"},
      ssh_worker_hosts: [],
      workspace_root: Path.join(test_root, "workspaces")
    }
  end

  defp live_worker_setup!(:ssh, run_id, test_root) when is_binary(run_id) and is_binary(test_root) do
    case live_ssh_worker_hosts() do
      [] ->
        live_docker_worker_setup!(run_id, test_root)

      _hosts ->
        live_ssh_worker_setup!(run_id)
    end
  end

  defp live_workflow_profile_options(:joined_coding_pr_delivery) do
    %{
      "requirements" => %{
        "change_proposal" => true,
        "typed_tracker_tools" => true,
        "typed_repo_tools" => true
      },
      "execution_profiles" => %{
        "allowed" => ["land"]
      }
    }
  end

  defp live_workflow_profile_options(_mode) do
    %{
      "requirements" => %{
        "change_proposal" => false,
        "typed_tracker_tools" => true,
        "typed_repo_tools" => false
      },
      "execution_profiles" => %{
        "allowed" => ["land"]
      }
    }
  end

  defp live_repo_config(:joined_coding_pr_delivery) do
    repository = System.get_env("SOURCE_REPO_PROVIDER_REPOSITORY") || @default_repository
    base_branch = System.get_env("SOURCE_REPO_BASE_BRANCH") || @default_base_branch
    branch_prefix = System.get_env("SOURCE_REPO_BRANCH_WORK_PREFIX") || @default_branch_prefix
    remote_url = System.get_env("SOURCE_REPO_URL") || "https://github.com/#{repository}.git"

    %{
      repository: repository,
      remote_url: remote_url,
      base_branch: base_branch,
      branch_prefix: branch_prefix,
      branch: live_repo_branch(branch_prefix)
    }
  end

  defp live_repo_config(_mode), do: nil

  defp live_repo_workflow_options(nil), do: []

  defp live_repo_workflow_options(repo_live) when is_map(repo_live) do
    [
      repo_path: "repo",
      repo_base_branch: repo_live.base_branch,
      repo_remote_name: "origin",
      repo_remote_url: repo_live.remote_url,
      repo_branch_work_prefix: repo_live.branch_prefix,
      repo_provider_kind: "github",
      repo_provider_repository: repo_live.repository,
      hook_after_create: live_repo_after_create_hook(repo_live)
    ]
  end

  defp live_repo_after_create_hook(repo_live) when is_map(repo_live) do
    "git clone --depth 1 --branch #{shell_escape(repo_live.base_branch)} #{shell_escape(repo_live.remote_url)} repo\n" <>
      "git -C repo config user.name 'Symphony Live Smoke'\n" <>
      "git -C repo config user.email 'symphony-live@example.invalid'"
  end

  defp live_repo_branch(branch_prefix) when is_binary(branch_prefix) do
    prefix = String.trim_trailing(branch_prefix, "/")
    suffix = "coding-pr-delivery-#{System.system_time(:second)}-#{System.unique_integer([:positive])}"

    case prefix do
      "" -> suffix
      _prefix -> prefix <> "/" <> suffix
    end
  end

  defp fetch_open_change_proposal_for_branch!(repository, branch)
       when is_binary(repository) and is_binary(branch) do
    case CommandEnv.system_cmd(
           "gh",
           [
             "pr",
             "list",
             "--repo",
             repository,
             "--head",
             branch,
             "--state",
             "open",
             "--json",
             "number,url",
             "--jq",
             ".[0]"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.trim()
        |> case do
          "" ->
            flunk("expected open GitHub change proposal for #{repository} branch #{branch}")

          "null" ->
            flunk("expected open GitHub change proposal for #{repository} branch #{branch}")

          json ->
            case Jason.decode(json) do
              {:ok, %{"number" => number, "url" => url}} when is_binary(url) ->
                %{number: number, url: url}

              {:ok, payload} ->
                flunk("unexpected GitHub change proposal payload: #{inspect(payload)}")

              {:error, reason} ->
                flunk("failed to decode GitHub change proposal payload #{inspect(json)}: #{inspect(reason)}")
            end
        end

      {output, status} ->
        flunk("failed to fetch GitHub change proposal for #{repository} branch #{branch}: #{status} #{output}")
    end
  end

  defp cleanup_live_repo(nil), do: :ok

  defp cleanup_live_repo(%{repository: repository, branch: branch, remote_url: remote_url})
       when is_binary(repository) and is_binary(branch) and is_binary(remote_url) do
    close_open_prs_for_branch(repository, branch)
    delete_remote_branch(remote_url, branch)
  end

  defp close_open_prs_for_branch(repository, branch)
       when is_binary(repository) and is_binary(branch) do
    case CommandEnv.system_cmd(
           "gh",
           [
             "pr",
             "list",
             "--repo",
             repository,
             "--head",
             branch,
             "--state",
             "open",
             "--json",
             "number",
             "--jq",
             ".[].number"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.each(&close_pr(repository, &1))

      {output, status} ->
        Logger.warning("Live e2e GitHub PR cleanup list failed for #{repository} #{branch}: #{status} #{output}")
    end
  end

  defp close_pr(repository, number) when is_binary(repository) and is_binary(number) do
    CommandEnv.system_cmd(
      "gh",
      [
        "pr",
        "close",
        number,
        "--repo",
        repository,
        "--comment",
        "Closing temporary Symphony joined coding PR delivery live probe."
      ],
      stderr_to_stdout: true
    )

    :ok
  end

  defp delete_remote_branch(remote_url, branch) when is_binary(remote_url) and is_binary(branch) do
    CommandEnv.system_cmd("git", ["push", remote_url, "--delete", branch], stderr_to_stdout: true)
    :ok
  end

  defp safe_file_name(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "joined-coding-pr-delivery"
      safe -> safe
    end
  end

  defp cleanup_live_worker_setup(%{cleanup: cleanup}) when is_function(cleanup, 0) do
    cleanup.()
  end

  defp cleanup_live_worker_setup(_worker_setup), do: :ok

  defp restart_orchestrator_if_needed do
    if is_nil(Process.whereis(SymphonyElixir.Orchestrator)) do
      :ok = restart_supervised_child(SymphonyElixir.Orchestrator)
    end
  end

  defp live_ssh_worker_setup!(run_id) when is_binary(run_id) do
    ssh_worker_hosts = live_ssh_worker_hosts()
    remote_test_root = Path.join(shared_remote_home!(ssh_worker_hosts), ".#{run_id}")
    remote_workspace_root = "~/.#{run_id}/workspaces"

    %{
      cleanup: fn -> cleanup_remote_test_root(remote_test_root, ssh_worker_hosts) end,
      agent_provider_options: %{command: "codex app-server"},
      ssh_worker_hosts: ssh_worker_hosts,
      workspace_root: remote_workspace_root
    }
  end

  defp live_docker_worker_setup!(run_id, test_root) when is_binary(run_id) and is_binary(test_root) do
    ssh_root = Path.join(test_root, "live-docker-ssh")
    key_path = Path.join(ssh_root, "id_ed25519")
    config_path = Path.join(ssh_root, "config")
    auth_json_path = @default_docker_auth_json
    worker_ports = reserve_tcp_ports(@docker_worker_count)
    worker_hosts = Enum.map(worker_ports, &"localhost:#{&1}")
    project_name = docker_project_name(run_id)
    previous_ssh_config = System.get_env("SYMPHONY_SSH_CONFIG")

    base_cleanup = fn ->
      restore_env("SYMPHONY_SSH_CONFIG", previous_ssh_config)
      docker_compose_down(project_name, docker_compose_env(worker_ports, auth_json_path, key_path <> ".pub"))
    end

    result =
      try do
        File.mkdir_p!(ssh_root)
        generate_ssh_keypair!(key_path)
        write_docker_ssh_config!(config_path, key_path)
        System.put_env("SYMPHONY_SSH_CONFIG", config_path)

        docker_compose_up!(project_name, docker_compose_env(worker_ports, auth_json_path, key_path <> ".pub"))
        wait_for_ssh_hosts!(worker_hosts)
        remote_test_root = Path.join(shared_remote_home!(worker_hosts), ".#{run_id}")
        remote_workspace_root = "~/.#{run_id}/workspaces"

        %{
          cleanup: fn ->
            cleanup_remote_test_root(remote_test_root, worker_hosts)
            base_cleanup.()
          end,
          agent_provider_options: %{command: "codex app-server"},
          ssh_worker_hosts: worker_hosts,
          workspace_root: remote_workspace_root
        }
      rescue
        error ->
          {:error, error, __STACKTRACE__}
      catch
        kind, reason ->
          {:caught, kind, reason, __STACKTRACE__}
      end

    case result do
      %{ssh_worker_hosts: _hosts} = worker_setup ->
        worker_setup

      {:error, error, stacktrace} ->
        base_cleanup.()
        reraise(error, stacktrace)

      {:caught, kind, reason, stacktrace} ->
        base_cleanup.()
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp live_ssh_worker_hosts do
    System.get_env("SYMPHONY_LIVE_SSH_WORKER_HOSTS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp cleanup_remote_test_root(test_root, ssh_worker_hosts)
       when is_binary(test_root) and is_list(ssh_worker_hosts) do
    Enum.each(ssh_worker_hosts, fn worker_host ->
      _ = SSH.run(worker_host, "rm -rf #{shell_escape(test_root)}", stderr_to_stdout: true)
    end)
  end

  defp shared_remote_home!([first_host | rest] = worker_hosts) when is_binary(first_host) and rest != [] do
    homes =
      worker_hosts
      |> Enum.map(fn worker_host -> {worker_host, remote_home!(worker_host)} end)

    [{_host, home} | _remaining] = homes

    if Enum.all?(homes, fn {_host, other_home} -> other_home == home end) do
      home
    else
      flunk("expected all live SSH workers to share one home directory, got: #{inspect(homes)}")
    end
  end

  defp shared_remote_home!([worker_host]) when is_binary(worker_host), do: remote_home!(worker_host)
  defp shared_remote_home!(_worker_hosts), do: flunk("expected at least one live SSH worker host")

  defp remote_home!(worker_host) when is_binary(worker_host) do
    case SSH.run(worker_host, "printf '%s\\n' \"$HOME\"", stderr_to_stdout: true) do
      {:ok, {output, 0}} ->
        output
        |> String.trim()
        |> case do
          "" -> flunk("expected non-empty remote home for #{worker_host}")
          home -> home
        end

      {:ok, {output, status}} ->
        flunk("failed to resolve remote home for #{worker_host} (status #{status}): #{inspect(output)}")

      {:error, reason} ->
        flunk("failed to resolve remote home for #{worker_host}: #{inspect(reason)}")
    end
  end

  defp reserve_tcp_ports(count) when is_integer(count) and count > 0 do
    reserve_tcp_ports(count, MapSet.new(), [])
  end

  defp reserve_tcp_ports(0, _seen, ports), do: Enum.reverse(ports)

  defp reserve_tcp_ports(remaining, seen, ports) do
    port = reserve_tcp_port!()

    if MapSet.member?(seen, port) do
      reserve_tcp_ports(remaining, seen, ports)
    else
      reserve_tcp_ports(remaining - 1, MapSet.put(seen, port), [port | ports])
    end
  end

  defp reserve_tcp_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, {:active, false}, {:reuseaddr, true}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp generate_ssh_keypair!(key_path) when is_binary(key_path) do
    case System.find_executable("ssh-keygen") do
      nil ->
        flunk("docker worker mode requires `ssh-keygen` on PATH")

      executable ->
        key_dir = Path.dirname(key_path)
        File.mkdir_p!(key_dir)
        File.rm_rf(key_path)
        File.rm_rf(key_path <> ".pub")

        case CommandEnv.system_cmd(executable, ["-q", "-t", "ed25519", "-N", "", "-f", key_path], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, status} -> flunk("failed to generate live docker ssh key (status #{status}): #{inspect(output)}")
        end
    end
  end

  defp write_docker_ssh_config!(config_path, key_path)
       when is_binary(config_path) and is_binary(key_path) do
    config_contents = """
    Host localhost 127.0.0.1
      User root
      IdentityFile #{key_path}
      IdentitiesOnly yes
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR
    """

    File.mkdir_p!(Path.dirname(config_path))
    File.write!(config_path, config_contents)
  end

  defp docker_project_name(run_id) when is_binary(run_id) do
    run_id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]/, "-")
  end

  defp docker_compose_env(worker_ports, auth_json_path, authorized_key_path)
       when is_list(worker_ports) and is_binary(auth_json_path) and is_binary(authorized_key_path) do
    [
      {"SYMPHONY_LIVE_DOCKER_AUTH_JSON", auth_json_path},
      {"SYMPHONY_LIVE_DOCKER_AUTHORIZED_KEY", authorized_key_path},
      {"SYMPHONY_LIVE_DOCKER_WORKER_1_PORT", Integer.to_string(Enum.at(worker_ports, 0))},
      {"SYMPHONY_LIVE_DOCKER_WORKER_2_PORT", Integer.to_string(Enum.at(worker_ports, 1))}
    ]
  end

  defp docker_compose_up!(project_name, env) when is_binary(project_name) and is_list(env) do
    args = ["compose", "-f", @docker_compose_file, "-p", project_name, "up", "-d", "--build"]

    case CommandEnv.system_cmd("docker", args, cd: @docker_support_dir, env: env, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        flunk("failed to start live docker workers (status #{status}): #{inspect(output)}")
    end
  end

  defp docker_compose_down(project_name, env) when is_binary(project_name) and is_list(env) do
    _ =
      CommandEnv.system_cmd(
        "docker",
        ["compose", "-f", @docker_compose_file, "-p", project_name, "down", "-v", "--remove-orphans"],
        cd: @docker_support_dir,
        env: env,
        stderr_to_stdout: true
      )

    :ok
  end

  defp wait_for_ssh_hosts!(worker_hosts) when is_list(worker_hosts) do
    deadline = System.monotonic_time(:millisecond) + 60_000

    Enum.each(worker_hosts, fn worker_host ->
      wait_for_ssh_host!(worker_host, deadline)
    end)
  end

  defp wait_for_ssh_host!(worker_host, deadline_ms) when is_binary(worker_host) do
    case SSH.run(worker_host, "printf ready", stderr_to_stdout: true) do
      {:ok, {"ready", 0}} ->
        :ok

      {:ok, {_output, _status}} ->
        retry_or_flunk_ssh_host(worker_host, deadline_ms)

      {:error, _reason} ->
        retry_or_flunk_ssh_host(worker_host, deadline_ms)
    end
  end

  defp retry_or_flunk_ssh_host(worker_host, deadline_ms) do
    if System.monotonic_time(:millisecond) < deadline_ms do
      Process.sleep(1_000)
      wait_for_ssh_host!(worker_host, deadline_ms)
    else
      flunk("timed out waiting for SSH worker #{worker_host} to accept connections")
    end
  end
end
