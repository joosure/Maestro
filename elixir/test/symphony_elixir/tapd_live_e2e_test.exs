defmodule SymphonyElixir.TapdLiveE2ETest do
  use SymphonyElixir.TestSupport

  require Logger

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.AgentProvider.Codex.AppServer
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Tracker.Tapd.Client

  @moduletag :live_e2e
  # Keep the ExUnit envelope longer than the provider turn/stall timeout so
  # live failures can unwind through normal cleanup instead of killing the test.
  @moduletag timeout: 1_200_000

  @result_file "TAPD_LIVE_E2E_RESULT.txt"
  @required_env_vars ~w[TAPD_API_USER TAPD_API_PASSWORD TAPD_WORKSPACE_ID]
  @github_pr_env_var "SYMPHONY_RUN_TAPD_LIVE_PR_E2E"
  @github_land_env_var "SYMPHONY_RUN_TAPD_LIVE_LAND_E2E"
  @github_rework_env_var "SYMPHONY_RUN_TAPD_LIVE_REWORK_E2E"
  @source_repo_url_env_var "SOURCE_REPO_URL"
  @source_repo_base_branch_env_var "SOURCE_REPO_BASE_BRANCH"
  @source_repo_provider_required_pr_label_env_var "SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL"
  @symphony_pr_label "symphony"
  @route_policy_active_route_keys [:planning, :developing, :merging, :rework]
  @route_policy_terminal_route_keys [:resolved, :rejected]
  @live_retry_delays_ms [1_000, 2_000, 5_000, 10_000, 20_000]
  @route_policy_state_env_vars [
    planning: "TAPD_ROUTE_POLICY_PLANNING_STATE",
    developing: "TAPD_ROUTE_POLICY_DEVELOPING_STATE",
    review: "TAPD_ROUTE_POLICY_REVIEW_STATE",
    merging: "TAPD_ROUTE_POLICY_MERGING_STATE",
    rework: "TAPD_ROUTE_POLICY_REWORK_STATE",
    resolved: "TAPD_ROUTE_POLICY_RESOLVED_STATE",
    rejected: "TAPD_ROUTE_POLICY_REJECTED_STATE"
  ]
  @preferred_terminal_states ~w[resolved done completed closed fixed accepted]
  @avoided_terminal_states ~w[rejected reject canceled cancelled duplicate invalid]
  @live_e2e_skip_reason if(
                          System.get_env("SYMPHONY_RUN_TAPD_LIVE_E2E") != "1",
                          do: "set SYMPHONY_RUN_TAPD_LIVE_E2E=1 to enable the real TAPD/Codex end-to-end test"
                        )
  @reuse_live_e2e_skip_reason if(
                                System.get_env("SYMPHONY_RUN_TAPD_LIVE_E2E") != "1" or
                                  System.get_env(@github_pr_env_var) == "1" or
                                  System.get_env(@github_land_env_var) == "1" or
                                  System.get_env(@github_rework_env_var) == "1",
                                do: "set only SYMPHONY_RUN_TAPD_LIVE_E2E=1 to enable the plain TAPD comment reuse live test"
                              )
  @route_policy_live_e2e_skip_reason if(
                                       System.get_env("SYMPHONY_RUN_TAPD_LIVE_E2E") != "1" or
                                         Enum.any?(@route_policy_state_env_vars, fn {_route_key, env_var} ->
                                           case System.get_env(env_var) do
                                             value when is_binary(value) -> String.trim(value) == ""
                                             _ -> true
                                           end
                                         end),
                                       do: "set SYMPHONY_RUN_TAPD_LIVE_E2E=1 and TAPD_ROUTE_POLICY_*_STATE env vars to enable TAPD route-policy live smoke tests"
                                     )

  test "tapd live prompt includes GitHub handoff instructions when PR mode is enabled" do
    prompt =
      tapd_live_prompt(
        "53070854",
        "done",
        "run-123",
        %{
          flow: :pr,
          base_branch: "main",
          branch_name: "tapd-live-e2e/run-123",
          label: @symphony_pr_label
        }
      )

    assert prompt =~ "Call inventory capability `repo.push`"
    assert prompt =~ "Call inventory capability `repo.create_or_update_change_proposal`"
    assert prompt =~ "labels: [\"symphony\"]"
    assert prompt =~ "ensure the GitHub PR has label `symphony`"
    assert prompt =~ "pr_url=<GitHub PR URL or not-created>"
    refute prompt =~ "repo-provider\" pr-create"
    refute prompt =~ "repo-provider\" pr-edit"
    refute prompt =~ "repo-provider\" pr-add-label"
    refute prompt =~ "gh pr create"
    refute prompt =~ "gh pr edit"
  end

  test "tapd live prompt does not require a GitHub label when PR mode label is disabled" do
    prompt =
      tapd_live_prompt(
        "53070854",
        "done",
        "run-123",
        %{
          flow: :pr,
          base_branch: "master",
          branch_name: "tapd-live-e2e/run-123",
          label: nil
        }
      )

    assert prompt =~ "update a GitHub PR targeting `master`"
    refute prompt =~ "ensure the GitHub PR has label"
    refute prompt =~ "--add-label"
  end

  test "tapd live prompt includes merge instructions when land mode is enabled" do
    prompt =
      tapd_live_prompt(
        "53070854",
        "done",
        "run-123",
        %{
          flow: :land,
          base_branch: "main",
          branch_name: "tapd-live-e2e/run-123",
          label: @symphony_pr_label
        }
      )

    assert prompt =~ "Merge the GitHub PR after it is ready."
    assert prompt =~ "Open `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists"
    assert prompt =~ ~s("${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-merge --squash)
    assert prompt =~ "Confirm the PR state is `MERGED`"
    assert prompt =~ "pr_state=<OPEN|MERGED|not-created>"
    refute prompt =~ "gh pr merge"
  end

  test "tapd live prompt includes fresh-branch instructions when rework mode is enabled" do
    prompt =
      tapd_live_prompt(
        "53070854",
        "done",
        "run-123",
        %{
          flow: :rework,
          base_branch: "main",
          branch_name: "tapd-live-e2e/run-123",
          label: @symphony_pr_label,
          seed_pr_url: "https://github.com/acme/repo/pull/1",
          seed_branch_name: "tapd-live-e2e/stale-run-123"
        }
      )

    assert prompt =~ "Close the stale PR without merging it"
    assert prompt =~ ~s("${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-close https://github.com/acme/repo/pull/1 --comment)
    assert prompt =~ "Create a fresh branch from `origin/main` named `tapd-live-e2e/run-123`"
    assert prompt =~ "previous_pr_url=https://github.com/acme/repo/pull/1"
    assert prompt =~ "rework_action=fresh-branch"
    refute prompt =~ "gh pr close"
  end

  test "tapd live prompt records no-pr handoff details when PR mode is disabled" do
    prompt = tapd_live_prompt("53070854", "done", "run-123", nil)

    assert prompt =~ "### Plan"
    assert prompt =~ "### Acceptance Criteria"
    assert prompt =~ "tapd_upsert_workpad"
    assert prompt =~ "Set `pr_url=not-created`"
    assert prompt =~ "pr_url=not-created"
    refute prompt =~ "gh pr create"
  end

  test "tapd live reuse prompt requires reusing the existing comment id" do
    prompt = tapd_live_reuse_prompt("53070854", "resolved", "run-123", "comment-9", "rerun-2")

    assert prompt =~ "It must have id `comment-9`"
    assert prompt =~ "Do not create a new TAPD comment."
    assert prompt =~ "tapd live e2e reuse: {{ issue.identifier }}"
    assert prompt =~ "rerun_token=rerun-2"
  end

  @tag skip: @live_e2e_skip_reason
  test "self-provisions a TAPD story and completes it through typed TAPD tools" do
    base_config = tapd_live_config!()

    with_live_story_context(base_config, fn config, cleanup_key ->
      issue =
        prepare_live_issue!(
          config,
          tapd_live_prompt(
            config.workspace_id,
            config.target_state,
            config.run_id,
            config.github_pr
          )
        )

      {runtime_info, codex_updates} = run_issue_and_collect!(issue)
      assert_default_live_completion!(config, issue, runtime_info, codex_updates, cleanup_key)
    end)
  end

  @tag skip: @reuse_live_e2e_skip_reason
  test "reuses the existing TAPD workpad comment across reruns" do
    base_config = tapd_live_config!()

    with_live_story_context(base_config, fn config, cleanup_key ->
      issue =
        prepare_live_issue!(
          config,
          tapd_live_prompt(
            config.workspace_id,
            config.target_state,
            config.run_id,
            config.github_pr
          )
        )

      {runtime_info, codex_updates} = run_issue_and_collect!(issue)

      first_run =
        assert_default_live_completion!(config, issue, runtime_info, codex_updates, cleanup_key)

      reopen_state = reopen_story_for_reuse!(config)
      rerun_token = "rerun-#{System.unique_integer([:positive])}"

      reused_issue =
        prepare_live_issue!(
          config,
          tapd_live_reuse_prompt(
            config.workspace_id,
            config.target_state,
            config.run_id,
            first_run.created_comment_id,
            rerun_token
          ),
          expected_state: reopen_state
        )

      {reused_runtime_info, reused_codex_updates} = run_issue_and_collect!(reused_issue)

      assert_reuse_live_completion!(
        config,
        reused_issue,
        reused_runtime_info,
        reused_codex_updates,
        first_run.created_comment_id,
        rerun_token
      )
    end)
  end

  @tag skip: @route_policy_live_e2e_skip_reason
  test "tapd live route policy transition_then_dispatch moves planning stories before dispatch" do
    base_config =
      tapd_live_config!()
      |> Map.put(:route_policy_config, tapd_route_policy_live_config!())

    with_live_story_context(base_config, fn config, _cleanup_key ->
      config =
        config
        |> Map.put(:policy_by_route_key, %{
          "planning" => %{"action" => "transition_then_dispatch", "transition_target" => "developing"}
        })
        |> Map.put(:agent_provider_options, %{command: create_fake_codex_command!(config.test_root)})

      issue =
        prepare_live_orchestrator_issue!(
          config,
          tapd_route_policy_live_prompt(config.run_id, "transition_then_dispatch"),
          raw_state!(config, :planning)
        )

      {returned_state, log} = run_live_orchestrator_poll_cycle!()
      running_entry = Map.fetch!(returned_state.running, issue.id)
      {runtime_info, codex_updates} = collect_run_messages!(issue.id)

      assert runtime_info.run_id == running_entry.run_id
      assert is_binary(runtime_info.workspace_path)
      assert Enum.any?(codex_updates, &(&1.event == :session_started))
      assert Enum.any?(codex_updates, &(&1.event == :turn_completed))

      [%Issue{} = refreshed_issue] = live_fetch_issue_states_by_ids!([config.story_id])
      assert refreshed_issue.state == raw_state!(config, :developing)

      assert log =~ "route_transition_succeeded"
      assert log =~ "issue_dispatch_started"

      stop_running_entry(running_entry)
      flush_orchestrator_test_messages()
    end)
  end

  @tag skip: @route_policy_live_e2e_skip_reason
  test "tapd live route policy wait skips dispatch while preserving the planning story state" do
    base_config =
      tapd_live_config!()
      |> Map.put(:route_policy_config, tapd_route_policy_live_config!())

    with_live_story_context(base_config, fn config, _cleanup_key ->
      config =
        Map.put(config, :policy_by_route_key, %{
          "planning" => %{"action" => "wait"}
        })

      issue =
        prepare_live_orchestrator_issue!(
          config,
          tapd_route_policy_live_prompt(config.run_id, "wait"),
          raw_state!(config, :planning)
        )

      {returned_state, log} = run_live_orchestrator_poll_cycle!()

      refute Map.has_key?(returned_state.running, issue.id)
      issue_id = issue.id

      [%Issue{} = refreshed_issue] = live_fetch_issue_states_by_ids!([config.story_id])
      assert refreshed_issue.state == raw_state!(config, :planning)

      assert log =~ "issue_dispatch_skipped"
      assert log =~ "route_preparation_skipped"

      refute_receive {:worker_runtime_info, ^issue_id, _}, 500
      refute_receive {:agent_worker_update, ^issue_id, _}, 500
      flush_orchestrator_test_messages()
    end)
  end

  @tag skip: @route_policy_live_e2e_skip_reason
  test "tapd live route policy stop skips dispatch while preserving the planning story state" do
    base_config =
      tapd_live_config!()
      |> Map.put(:route_policy_config, tapd_route_policy_live_config!())

    with_live_story_context(base_config, fn config, _cleanup_key ->
      config =
        Map.put(config, :policy_by_route_key, %{
          "planning" => %{"action" => "stop"}
        })

      issue =
        prepare_live_orchestrator_issue!(
          config,
          tapd_route_policy_live_prompt(config.run_id, "stop"),
          raw_state!(config, :planning)
        )

      {returned_state, log} = run_live_orchestrator_poll_cycle!()

      refute Map.has_key?(returned_state.running, issue.id)
      issue_id = issue.id

      [%Issue{} = refreshed_issue] = live_fetch_issue_states_by_ids!([config.story_id])
      assert refreshed_issue.state == raw_state!(config, :planning)

      assert log =~ "issue_dispatch_skipped"
      assert log =~ "route_preparation_skipped"

      refute_receive {:worker_runtime_info, ^issue_id, _}, 500
      refute_receive {:agent_worker_update, ^issue_id, _}, 500
      flush_orchestrator_test_messages()
    end)
  end

  defp with_live_story_context(base_config, fun) when is_map(base_config) and is_function(fun, 2) do
    cleanup_key = {__MODULE__, :github_pr_cleanup, base_config.run_id}
    story_cleanup_key = {__MODULE__, :tapd_story_cleanup, base_config.run_id}
    original_workflow_path = Workflow.workflow_file_path()
    orchestrator_pid = Process.whereis(SymphonyElixir.Orchestrator)

    try do
      Process.delete(cleanup_key)
      Process.delete(story_cleanup_key)

      provisioned_story = provision_live_story!(base_config)
      Process.put(story_cleanup_key, story_cleanup(base_config, provisioned_story))
      config = runtime_config_from_story!(base_config, provisioned_story)

      if is_pid(orchestrator_pid) do
        assert :ok = terminate_supervised_child(SymphonyElixir.Orchestrator)
      end

      Workflow.set_workflow_file_path(config.workflow_file)
      fun.(config, cleanup_key)
    after
      best_effort_cleanup_github_pr(base_config.github_pr, Process.get(cleanup_key))
      best_effort_cleanup_github_repo(base_config.github_pr)
      Process.delete(cleanup_key)
      story_cleanup = Process.get(story_cleanup_key)

      best_effort_finalize_story(
        story_cleanup && story_cleanup.tracker,
        story_cleanup && story_cleanup.story_id,
        story_cleanup && story_cleanup.target_state
      )

      Process.delete(story_cleanup_key)
      restart_orchestrator_if_needed()
      Workflow.set_workflow_file_path(original_workflow_path)
      File.rm_rf(base_config.test_root)
    end
  end

  defp prepare_live_issue!(config, prompt, opts \\ [])
       when is_map(config) and is_binary(prompt) and is_list(opts) do
    write_live_workflow!(config, prompt)

    expected_state =
      Keyword.get(opts, :expected_state) ||
        List.first(config.active_states) ||
        flunk("expected at least one TAPD active state for live test")

    assert Tracker.project_url() ==
             "https://www.tapd.cn/#{config.workspace_id}/prong/stories/view"

    dynamic_tool_names =
      DynamicTool.tool_specs()
      |> Enum.map(&Map.fetch!(&1, "name"))

    refute "tapd_api" in dynamic_tool_names
    assert "tapd_issue_snapshot" in dynamic_tool_names
    assert "tapd_move_issue" in dynamic_tool_names
    assert "tapd_upsert_workpad" in dynamic_tool_names

    [%Issue{} = active_issue] = live_fetch_issue_states_by_ids!([config.story_id])
    assert active_issue.id == config.story_id
    assert active_issue.state == expected_state

    candidate_issues = live_fetch_candidate_issues!()
    assert Enum.any?(candidate_issues, &(&1.id == config.story_id))

    issue = Enum.find(candidate_issues, &(&1.id == config.story_id))
    assert %Issue{} = issue

    probe_workspace = create_probe_workspace!(config.workspace_root)

    {:ok, tool_context} =
      SymphonyElixir.Agent.DynamicTool.WorkflowPlan.from_opts(
        issue: issue,
        issue_id: issue.id,
        issue_identifier: issue.identifier
      )

    {:ok, app_session} =
      AppServer.start_session(
        probe_workspace,
        codex_app_server_opts(probe_workspace, tool_context: tool_context)
      )

    try do
      tool_names = Enum.map(app_session.dynamic_tool_specs, &Map.fetch!(&1, "name"))
      refute "tapd_api" in tool_names
      assert "tapd_issue_snapshot" in tool_names
      assert "tapd_move_issue" in tool_names
      assert "tapd_upsert_workpad" in tool_names
    after
      assert :ok = AppServer.stop_session(app_session)
    end

    issue
  end

  defp write_live_workflow!(config, prompt) when is_map(config) and is_binary(prompt) do
    write_workflow_file!(config.workflow_file,
      tracker_kind: "tapd",
      tracker_endpoint: "https://api.tapd.cn",
      tracker_api_token: "$TAPD_API_USER",
      tracker_api_secret: "$TAPD_API_PASSWORD",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: config.active_states,
      tracker_terminal_states: config.terminal_states,
      tracker_state_phase_map: Map.get(config, :state_phase_map) || :default,
      tracker_raw_state_by_route_key: Map.get(config, :raw_state_by_route_key),
      tracker_policy_by_route_key: Map.get(config, :policy_by_route_key),
      tracker_platform: config.tracker_platform,
      poll_interval_ms: 5_000,
      workspace_root: config.workspace_root,
      repo_base_branch:
        (config.github_pr && config.github_pr.base_branch) ||
          get_in(config, [:source_repo, :base_branch]),
      repo_provider_required_pr_label:
        (config.github_pr && config.github_pr.label) ||
          get_in(config, [:source_repo, :label]),
      hook_after_create: after_create_hook(config),
      max_turns: 3,
      server_port: 0,
      workflow_profile: %{
        "kind" => "coding_pr_delivery",
        "version" => 1,
        "options" => %{
          "require_typed_tracker_tools" => true,
          "require_typed_repo_tools" => true
        }
      },
      agent_provider_options:
        Map.merge(Map.get(config, :agent_provider_options) || %{command: "codex app-server"}, %{
          approval_policy: "never",
          thread_sandbox: "danger-full-access",
          turn_sandbox_policy: %{"type" => "dangerFullAccess"},
          turn_timeout_ms: 600_000,
          stall_timeout_ms: 600_000
        }),
      observability_enabled: false,
      prompt: prompt
    )

    assert :ok = Config.validate!()
    assert :ok = restart_supervised_child(SymphonyElixir.HttpServer)
    assert is_integer(SymphonyElixir.HttpServer.bound_port())
  end

  defp run_issue_and_collect!(issue) do
    assert :ok = AgentRunner.run(issue, self(), max_turns: 3)
    collect_run_messages!(issue.id)
  end

  defp assert_default_live_completion!(config, issue, runtime_info, _codex_updates, cleanup_key)
       when is_map(config) and is_map(issue) and is_map(runtime_info) do
    result = read_worker_result!(runtime_info, @result_file)
    assert result =~ "identifier=#{issue.identifier}\n"
    assert result =~ "workspace_id=#{config.workspace_id}\n"
    assert result =~ "target_state=#{config.target_state}\n"

    branch_name = result_value!(result, "branch_name")
    commit_sha = result_value!(result, "commit_sha")
    pr_url = result_value!(result, "pr_url")
    pr_state = result_value!(result, "pr_state")

    assert String.trim(branch_name) != ""
    assert String.trim(commit_sha) != ""

    assert read_worker_repo_file!(runtime_info, "STATUS.txt") ==
             expected_status_contents(issue.identifier, issue.id, config.target_state)

    workpad = read_worker_file!(runtime_info, ".symphony-tapd-workpad.md")
    assert workpad =~ "### Plan"
    assert workpad =~ "### Acceptance Criteria"
    assert workpad =~ "run_id=#{config.run_id}"
    assert workpad =~ "- [x] 1. Update STATUS.txt"
    assert workpad =~ "- [x] 2. Commit the repository change"
    assert workpad =~ "- [x] 3. Sync TAPD workpad comment"
    assert workpad =~ "- [x] 4. Record handoff details"

    assert workpad =~
             "- [x] `repo/STATUS.txt` records the current Story identifier, full Story id, and target state `#{config.target_state}`"

    assert workpad =~ "- [x] TAPD workpad comment matches `.symphony-tapd-workpad.md`"
    assert workpad =~ "- [x] Story reread confirms TAPD status `#{config.target_state}`"
    assert workpad =~ "- [x] git -C repo diff --check (pass)"
    assert workpad =~ "branch_name: #{branch_name}"
    assert workpad =~ "commit_sha: #{commit_sha}"
    assert workpad =~ "pr_url: #{pr_url}"
    assert workpad =~ "pr_state: #{pr_state}"

    full_head_sha = String.trim(read_git_output!(runtime_info, ["rev-parse", "HEAD"]))
    assert String.length(commit_sha) >= 7
    assert String.starts_with?(full_head_sha, commit_sha)
    assert read_git_output!(runtime_info, ["rev-parse", "--abbrev-ref", "HEAD"]) == "#{branch_name}\n"

    assert_git_subject!(runtime_info, config.github_pr, issue.identifier)

    assert read_git_output!(runtime_info, ["status", "--short"]) == ""

    assert_dynamic_tool_succeeded!(runtime_info, "tapd_issue_snapshot")
    assert_dynamic_tool_succeeded!(runtime_info, "tapd_upsert_workpad")
    refute_retired_raw_tools_called!(runtime_info)

    story_comments = fetch_story_comments!(config, issue.id)

    [created_comment_id] =
      story_comments
      |> Enum.filter(&workpad_comment?/1)
      |> Enum.map(&Map.fetch!(&1, "id"))

    persisted_workpad = comment_body_from_api!(story_comments, created_comment_id)

    assert normalize_multiline(persisted_workpad) == normalize_multiline(workpad)

    if config.github_pr do
      Process.put(cleanup_key, %{
        branch_name: branch_name,
        pr_url: pr_url,
        extra_pr_urls: cleanup_extra_pr_urls(config.github_pr)
      })

      assert pr_url =~ ~r/^https:\/\/github\.com\//

      pr_info = github_pull_request!(pr_url)
      assert pr_info["url"] == pr_url
      assert pr_info["baseRefName"] == config.github_pr.base_branch
      assert pr_info["headRefName"] == expected_pr_head_ref(config.github_pr, branch_name)

      label_names = Enum.map(pr_info["labels"], & &1["name"])

      if is_binary(config.github_pr.label) do
        assert config.github_pr.label in label_names
      end

      assert_github_flow!(config.github_pr, pr_info, result, branch_name)
    else
      assert pr_url == "not-created"
      assert pr_state == "not-created"
    end

    assert_dynamic_tool_succeeded!(runtime_info, "tapd_move_issue")

    [%Issue{} = refreshed_issue] = live_fetch_issue_states_by_ids!([config.story_id])
    assert refreshed_issue.state == config.target_state

    remaining_candidates = live_fetch_candidate_issues!()
    refute Enum.any?(remaining_candidates, &(&1.id == config.story_id))

    %{
      branch_name: branch_name,
      commit_sha: commit_sha,
      created_comment_id: created_comment_id,
      pr_state: pr_state,
      pr_url: pr_url,
      result: result,
      workpad: workpad
    }
  end

  defp assert_reuse_live_completion!(config, issue, runtime_info, _codex_updates, comment_id, rerun_token)
       when is_map(config) and is_map(issue) and is_map(runtime_info) do
    result = read_worker_result!(runtime_info, @result_file)
    assert result =~ "identifier=#{issue.identifier}\n"
    assert result =~ "workspace_id=#{config.workspace_id}\n"
    assert result =~ "target_state=#{config.target_state}\n"
    assert result_value!(result, "workpad_comment_id") == comment_id
    assert result_value!(result, "rerun_token") == rerun_token

    branch_name = result_value!(result, "branch_name")
    commit_sha = result_value!(result, "commit_sha")
    pr_url = result_value!(result, "pr_url")
    pr_state = result_value!(result, "pr_state")

    assert read_worker_repo_file!(runtime_info, "STATUS.txt") ==
             expected_reuse_status_contents(issue.identifier, issue.id, config.target_state, rerun_token)

    workpad = read_worker_file!(runtime_info, ".symphony-tapd-workpad.md")
    assert workpad =~ "### Plan"
    assert workpad =~ "rerun_token: #{rerun_token}"
    assert workpad =~ "- [x] TAPD workpad comment matches `.symphony-tapd-workpad.md`"
    assert workpad =~ "- [x] git -C repo diff --check (pass)"
    assert workpad =~ "branch_name: #{branch_name}"
    assert workpad =~ "commit_sha: #{commit_sha}"
    assert workpad =~ "pr_url: #{pr_url}"
    assert workpad =~ "pr_state: #{pr_state}"

    assert read_git_output!(runtime_info, ["log", "-1", "--pretty=%s"]) ==
             "tapd live e2e reuse: #{issue.identifier}\n"

    assert_dynamic_tool_succeeded!(runtime_info, "tapd_issue_snapshot")
    assert_dynamic_tool_succeeded!(runtime_info, "tapd_upsert_workpad")
    refute_retired_raw_tools_called!(runtime_info)

    story_comments = fetch_story_comments!(config, issue.id)

    workpad_comment_ids =
      story_comments
      |> Enum.filter(&workpad_comment?/1)
      |> Enum.map(&Map.fetch!(&1, "id"))

    assert workpad_comment_ids == [comment_id]

    persisted_workpad = comment_body_from_api!(story_comments, comment_id)
    assert normalize_multiline(persisted_workpad) == normalize_multiline(workpad)

    assert_dynamic_tool_succeeded!(runtime_info, "tapd_move_issue")

    [%Issue{} = refreshed_issue] = live_fetch_issue_states_by_ids!([config.story_id])
    assert refreshed_issue.state == config.target_state

    remaining_candidates = live_fetch_candidate_issues!()
    refute Enum.any?(remaining_candidates, &(&1.id == config.story_id))

    assert pr_url == "not-created"
    assert pr_state == "not-created"
  end

  defp tapd_live_config! do
    missing =
      Enum.reject(@required_env_vars, fn env_var ->
        value = System.get_env(env_var)
        is_binary(value) and String.trim(value) != ""
      end)

    if missing != [] do
      flunk("missing TAPD live e2e env vars: #{Enum.join(missing, ", ")}")
    end

    run_id = "symphony-tapd-live-e2e-#{System.unique_integer([:positive])}"
    test_root = Path.join(System.tmp_dir!(), run_id)
    workflow_root = Path.join(test_root, "workflow")
    workflow_file = Path.join(workflow_root, "WORKFLOW.md")
    workspace_root = Path.join(test_root, "workspaces")
    template_repo = Path.join(test_root, "template-repo")
    File.mkdir_p!(workflow_root)
    File.mkdir_p!(workspace_root)
    source_repo = source_repo_override_config()
    github_pr = maybe_github_pr_config!(run_id, test_root, source_repo)

    if is_nil(github_pr) and is_nil(source_repo) do
      create_template_repo!(template_repo)
    end

    workspace_id = System.fetch_env!("TAPD_WORKSPACE_ID")
    requested_workitem_type_id = env_value("TAPD_WORKITEM_TYPE_ID")
    requested_target_state = env_value("TAPD_TARGET_STATE")
    comment_author = env_value("TAPD_COMMENT_AUTHOR")
    bootstrap_tracker = bootstrap_tracker(workspace_id, comment_author)
    story_name = "Symphony TAPD Live E2E #{run_id}"

    %{
      test_root: test_root,
      workflow_file: workflow_file,
      workspace_root: workspace_root,
      template_repo: if(is_nil(github_pr) and is_nil(source_repo), do: template_repo, else: nil),
      source_repo: source_repo,
      workspace_id: workspace_id,
      bootstrap_tracker: bootstrap_tracker,
      comment_author: comment_author,
      requested_target_state: requested_target_state,
      requested_workitem_type_id: requested_workitem_type_id,
      github_pr: github_pr,
      run_id: run_id,
      story_name: story_name,
      story_description: "Symphony TAPD live e2e smoke #{run_id}"
    }
  end

  defp tapd_route_policy_live_config! do
    raw_state_by_route_key =
      Enum.reduce(@route_policy_state_env_vars, %{}, fn {route_key, env_var}, acc ->
        raw_state =
          env_value(env_var) ||
            flunk("missing TAPD route-policy live env var: #{env_var}")

        Map.put(acc, Atom.to_string(route_key), raw_state)
      end)

    %{
      active_states: Enum.map(@route_policy_active_route_keys, &Map.fetch!(raw_state_by_route_key, Atom.to_string(&1))),
      terminal_states: Enum.map(@route_policy_terminal_route_keys, &Map.fetch!(raw_state_by_route_key, Atom.to_string(&1))),
      state_phase_map:
        Enum.reduce(raw_state_by_route_key, %{}, fn {route_key, raw_state}, acc ->
          Map.put(acc, raw_state, route_phase_name(String.to_existing_atom(route_key)))
        end),
      raw_state_by_route_key: raw_state_by_route_key
    }
  end

  defp story_cleanup(base_config, provisioned_story) when is_map(base_config) and is_map(provisioned_story) do
    %{
      tracker: base_config.bootstrap_tracker,
      story_id: provisioned_story.story_id,
      target_state: provisioned_story.target_state
    }
  end

  defp provision_live_story!(config) do
    story = create_live_story!(config)
    workitem_type_id = normalize_string(Map.get(story, "workitem_type_id")) || config.requested_workitem_type_id
    first_states = fetch_workflow_states!(config.bootstrap_tracker, "/workflows/first_step", workitem_type_id)
    created_state = normalize_string(Map.get(story, "status"))
    active_states = [created_state | first_states] |> Enum.reject(&is_nil/1) |> Enum.uniq()
    terminal_states = fetch_workflow_states!(config.bootstrap_tracker, "/workflows/last_steps", workitem_type_id)
    target_state = select_target_state!(config.requested_target_state, terminal_states)

    %{
      story_id: Map.fetch!(story, "id"),
      workitem_type_id: workitem_type_id,
      active_states: active_states,
      terminal_states: terminal_states,
      target_state: target_state
    }
  end

  defp create_live_story!(config) do
    params =
      %{
        "name" => config.story_name,
        "description" => config.story_description
      }
      |> maybe_put_param("workitem_type_id", config.requested_workitem_type_id)

    case Client.request("POST", "/stories", params, live_request_opts(tracker: config.bootstrap_tracker)) do
      {:ok, body} ->
        body
        |> unwrap_success_payload!("/stories")
        |> unwrap_story!("/stories")

      {:error, reason} ->
        flunk("failed to create TAPD live smoke story: #{inspect(reason)}")
    end
  end

  defp runtime_config_from_story!(base_config, provisioned_story) do
    tracker_platform =
      %{"workspace_id" => base_config.workspace_id}
      |> maybe_put_param("workitem_type_id", provisioned_story.workitem_type_id)
      |> maybe_put_param("comment_author", base_config.comment_author)

    runtime_config = %{
      test_root: base_config.test_root,
      workflow_file: base_config.workflow_file,
      workspace_root: base_config.workspace_root,
      template_repo: base_config.template_repo,
      source_repo: base_config.source_repo,
      workspace_id: base_config.workspace_id,
      bootstrap_tracker: base_config.bootstrap_tracker,
      github_pr: base_config.github_pr,
      run_id: base_config.run_id,
      story_id: provisioned_story.story_id,
      active_states: provisioned_story.active_states,
      terminal_states: provisioned_story.terminal_states,
      target_state: provisioned_story.target_state,
      tracker_platform: tracker_platform
    }

    merge_route_policy_runtime_config(runtime_config, Map.get(base_config, :route_policy_config))
  end

  defp maybe_github_pr_config!(run_id, test_root, source_repo)
       when is_binary(run_id) and is_binary(test_root) do
    case github_flow!() do
      :none ->
        nil

      :pr ->
        repo_config = source_repo || current_repo_config!()

        %{
          flow: :pr,
          base_branch: repo_config.base_branch,
          branch_name: "tapd-live-e2e/#{run_id}",
          clone_url: repo_config.clone_url,
          label: repo_config.label,
          repo_name_with_owner: repo_config.repo_name_with_owner,
          repo_url: repo_config.repo_url
        }

      flow when flow in [:land, :rework] ->
        provision_github_smoke_repo!(run_id, test_root, flow, source_repo || current_repo_config!())
    end
  end

  defp github_flow! do
    enabled_flows =
      [
        {@github_pr_env_var, :pr},
        {@github_land_env_var, :land},
        {@github_rework_env_var, :rework}
      ]
      |> Enum.filter(fn {env_var, _flow} -> System.get_env(env_var) == "1" end)

    case enabled_flows do
      [] ->
        :none

      [{_env_var, flow}] ->
        flow

      flows ->
        enabled_env_vars = Enum.map_join(flows, ", ", fn {env_var, _flow} -> env_var end)
        flunk("enable only one TAPD live GitHub smoke mode at a time; enabled: #{enabled_env_vars}")
    end
  end

  defp provision_github_smoke_repo!(run_id, test_root, flow, source_repo)
       when is_binary(run_id) and is_binary(test_root) and flow in [:land, :rework] and is_map(source_repo) do
    owner = github_repo_owner!()
    repo_name = github_smoke_repo_name(run_id)
    repo_name_with_owner = "#{owner}/#{repo_name}"
    base_branch = source_repo.base_branch
    seed_repo = Path.join(test_root, "github-seed-repo")
    clone_url = "https://github.com/#{repo_name_with_owner}.git"

    gh_ok!(
      [
        "repo",
        "create",
        repo_name_with_owner,
        "--private",
        "--description",
        "Temporary Symphony TAPD live e2e smoke repository"
      ],
      "create temporary GitHub smoke repository"
    )

    try do
      gh_ok!(
        [
          "label",
          "create",
          source_repo.label || @symphony_pr_label,
          "--repo",
          repo_name_with_owner,
          "--color",
          "0e8a16",
          "--description",
          "Symphony-managed pull requests"
        ],
        "create temporary GitHub smoke label"
      )

      seed_github_smoke_repo!(seed_repo, clone_url, source_repo.clone_url, base_branch)

      github_pr = %{
        flow: flow,
        base_branch: base_branch,
        branch_name: "tapd-live-e2e/#{run_id}",
        clone_url: clone_url,
        label: source_repo.label || @symphony_pr_label,
        repo_name: repo_name,
        repo_name_with_owner: repo_name_with_owner,
        repo_url: "https://github.com/#{repo_name_with_owner}",
        temporary_repo?: true
      }

      case flow do
        :land ->
          github_pr

        :rework ->
          Map.merge(github_pr, create_stale_rework_pr!(github_pr, test_root, run_id))
      end
    rescue
      error ->
        best_effort_delete_github_repo(repo_name_with_owner)
        reraise(error, __STACKTRACE__)
    catch
      kind, reason ->
        best_effort_delete_github_repo(repo_name_with_owner)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp github_repo_owner! do
    case env_value("SYMPHONY_TAPD_LIVE_GITHUB_OWNER") do
      nil ->
        gh_output!(["api", "user", "--jq", ".login"], "resolve authenticated GitHub user")

      owner ->
        owner
    end
  end

  defp github_smoke_repo_name(run_id) when is_binary(run_id) do
    run_id
    |> String.replace(~r/[^A-Za-z0-9_.-]/, "-")
    |> then(&"symphony-tapd-live-#{&1}")
    |> String.slice(0, 90)
  end

  defp seed_github_smoke_repo!(seed_repo, clone_url, source_clone_url, base_branch)
       when is_binary(seed_repo) and is_binary(clone_url) and is_binary(source_clone_url) and
              is_binary(base_branch) do
    cmd_ok!(
      "git",
      ["clone", "--branch", base_branch, source_clone_url, seed_repo],
      "clone source repository for temporary GitHub smoke seed"
    )

    cmd_ok!(
      "git",
      ["-C", seed_repo, "remote", "set-url", "origin", clone_url],
      "point temporary GitHub smoke seed at temporary repository"
    )

    cmd_ok!(
      "git",
      ["-C", seed_repo, "push", "-u", "origin", base_branch],
      "push temporary GitHub smoke base branch"
    )
  end

  defp create_stale_rework_pr!(github_pr, test_root, run_id) when is_map(github_pr) do
    rework_repo = Path.join(test_root, "github-rework-seed")
    stale_branch_name = "tapd-live-e2e/stale-#{run_id}"

    cmd_ok!(
      "git",
      ["clone", "--depth", "1", "--branch", github_pr.base_branch, github_pr.clone_url, rework_repo],
      "clone temporary GitHub smoke repository for stale rework PR"
    )

    cmd_ok!(
      "git",
      ["-C", rework_repo, "config", "user.name", "TAPD Live E2E"],
      "configure stale rework git user"
    )

    cmd_ok!(
      "git",
      ["-C", rework_repo, "config", "user.email", "tapd-live-e2e@example.com"],
      "configure stale rework git email"
    )

    cmd_ok!(
      "git",
      ["-C", rework_repo, "switch", "-c", stale_branch_name],
      "create stale rework branch"
    )

    File.write!(
      Path.join(rework_repo, "STATUS.txt"),
      "stale rework branch\nrun_id=#{run_id}\n"
    )

    cmd_ok!("git", ["-C", rework_repo, "add", "STATUS.txt"], "stage stale rework status")
    cmd_ok!("git", ["-C", rework_repo, "commit", "-m", "tapd live e2e stale rework branch"], "commit stale rework status")
    cmd_ok!("git", ["-C", rework_repo, "push", "-u", "origin", stale_branch_name], "push stale rework branch")

    seed_pr_url =
      gh_output!(
        [
          "pr",
          "create",
          "--repo",
          github_pr.repo_name_with_owner,
          "--base",
          github_pr.base_branch,
          "--head",
          stale_branch_name,
          "--title",
          "tapd live e2e stale rework PR",
          "--body",
          "Temporary stale PR for TAPD live rework smoke."
        ],
        "create stale rework PR"
      )

    gh_ok!(
      ["pr", "edit", seed_pr_url, "--add-label", github_pr.label],
      "label stale rework PR"
    )

    gh_ok!(
      [
        "pr",
        "comment",
        seed_pr_url,
        "--body",
        "Reviewer request: close this stale PR and restart from a fresh branch."
      ],
      "add stale rework review comment"
    )

    %{
      seed_pr_url: seed_pr_url,
      seed_branch_name: stale_branch_name
    }
  end

  defp current_repo_origin_url! do
    git_root = git_repo_root!()

    case CommandEnv.system_cmd("git", ["remote", "get-url", "origin"], cd: git_root, stderr_to_stdout: true) do
      {output, 0} ->
        case String.trim(output) do
          "" -> flunk("current repo origin URL is empty")
          remote_url -> remote_url
        end

      {output, status} ->
        flunk("failed to resolve current repo origin URL: status=#{status} output=#{output}")
    end
  end

  defp current_repo_metadata! do
    git_root = git_repo_root!()

    case CommandEnv.system_cmd("gh", ["repo", "view", "--json", "nameWithOwner,url,defaultBranchRef"], cd: git_root, stderr_to_stdout: true) do
      {output, 0} ->
        Jason.decode!(output)

      {output, status} ->
        flunk("failed to resolve current GitHub repo metadata: status=#{status} output=#{output}")
    end
  end

  defp source_repo_override_config do
    case env_value(@source_repo_url_env_var) do
      nil ->
        nil

      clone_url ->
        {repo_name_with_owner, repo_url} = repo_identity_from_url!(clone_url)

        %{
          clone_url: clone_url,
          repo_name_with_owner: repo_name_with_owner,
          repo_url: repo_url,
          base_branch: source_repo_base_branch(remote_default_branch!(clone_url)),
          label: source_repo_label(nil)
        }
    end
  end

  defp current_repo_config! do
    repo_metadata = current_repo_metadata!()

    %{
      clone_url: current_repo_origin_url!(),
      repo_name_with_owner: repo_metadata["nameWithOwner"],
      repo_url: repo_metadata["url"],
      base_branch: source_repo_base_branch(get_in(repo_metadata, ["defaultBranchRef", "name"]) || "main"),
      label: source_repo_label(@symphony_pr_label)
    }
  end

  defp source_repo_base_branch(default_branch) when is_binary(default_branch) do
    env_value(@source_repo_base_branch_env_var) || default_branch
  end

  defp source_repo_label(default_label) do
    case System.get_env(@source_repo_provider_required_pr_label_env_var) do
      nil ->
        default_label

      configured ->
        normalize_string(configured)
    end
  end

  defp repo_identity_from_url!(clone_url) when is_binary(clone_url) do
    case Regex.run(~r/(?:github\.com[:\/])([^\/:]+)\/([^\/]+?)(?:\.git)?$/, clone_url, capture: :all_but_first) do
      [owner, repo] ->
        repo_name_with_owner = "#{owner}/#{repo}"
        {repo_name_with_owner, "https://github.com/#{repo_name_with_owner}"}

      _ ->
        flunk("failed to derive GitHub repo identity from SOURCE_REPO_URL=#{inspect(clone_url)}")
    end
  end

  defp remote_default_branch!(clone_url) when is_binary(clone_url) do
    case CommandEnv.system_cmd("git", ["ls-remote", "--symref", clone_url, "HEAD"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r{ref:\s+refs/heads/([^\s]+)\s+HEAD}, output, capture: :all_but_first) do
          [branch_name] ->
            branch_name

          _ ->
            flunk("failed to determine default branch for #{inspect(clone_url)}: #{output}")
        end

      {output, status} ->
        flunk("failed to inspect default branch for #{inspect(clone_url)}: status=#{status} output=#{output}")
    end
  end

  defp git_repo_root! do
    project_dir = Path.expand("../../..", __DIR__)

    case CommandEnv.system_cmd("git", ["rev-parse", "--show-toplevel"], cd: project_dir, stderr_to_stdout: true) do
      {output, 0} ->
        String.trim(output)

      {output, status} ->
        flunk("failed to resolve git repo root: status=#{status} output=#{output}")
    end
  end

  defp fetch_workflow_states!(tracker, "/workflows/first_step" = path, workitem_type_id) do
    params =
      %{"system" => "story"}
      |> maybe_put_param("workitem_type_id", workitem_type_id)

    case Client.request("GET", path, params, live_request_opts(tracker: tracker)) do
      {:ok, body} ->
        body
        |> unwrap_success_payload!(path)
        |> decode_workflow_states!(path)

      {:error, reason} ->
        flunk("failed to fetch TAPD workflow states for #{path}: #{inspect(reason)}")
    end
  end

  defp fetch_workflow_states!(tracker, "/workflows/last_steps" = path, workitem_type_id) do
    params =
      %{"system" => "story", "type" => "status"}
      |> maybe_put_param("workitem_type_id", workitem_type_id)

    case Client.request("GET", path, params, live_request_opts(tracker: tracker)) do
      {:ok, body} ->
        body
        |> unwrap_success_payload!(path)
        |> decode_workflow_states!(path)

      {:error, reason} ->
        flunk("failed to fetch TAPD workflow states for #{path}: #{inspect(reason)}")
    end
  end

  defp select_target_state!(requested_target_state, terminal_states) when is_list(terminal_states) do
    normalized_terminal_states =
      terminal_states
      |> Enum.map(&normalize_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case normalize_string(requested_target_state) do
      nil ->
        Enum.find(normalized_terminal_states, &preferred_terminal_state?/1) ||
          Enum.find(normalized_terminal_states, &(not avoided_terminal_state?(&1))) ||
          List.first(normalized_terminal_states) ||
          flunk("TAPD workflow returned no terminal states for live smoke")

      target_state ->
        if target_state in normalized_terminal_states do
          target_state
        else
          flunk("requested TAPD target state #{inspect(target_state)} is not one of #{inspect(normalized_terminal_states)}")
        end
    end
  end

  defp preferred_terminal_state?(state_name) when is_binary(state_name) do
    state_name in @preferred_terminal_states
  end

  defp avoided_terminal_state?(state_name) when is_binary(state_name) do
    state_name in @avoided_terminal_states
  end

  defp bootstrap_tracker(workspace_id, comment_author) when is_binary(workspace_id) do
    platform =
      %{"workspace_id" => workspace_id}
      |> maybe_put_param("comment_author", comment_author)

    %{
      kind: "tapd",
      endpoint: "https://api.tapd.cn",
      auth: %{
        "api_key" => System.fetch_env!("TAPD_API_USER"),
        "api_secret" => System.fetch_env!("TAPD_API_PASSWORD")
      },
      lifecycle: %{
        "active_states" => [],
        "terminal_states" => []
      },
      provider: %{"platform" => platform}
    }
  end

  defp unwrap_success_payload!(body, path) when is_binary(path) do
    case Client.decode_success_envelope(path, body) do
      {:ok, data} -> data
      {:error, reason} -> flunk("unexpected TAPD payload for #{path}: #{inspect(reason)}")
    end
  end

  defp unwrap_story!(%{"Story" => %{} = story}, _path), do: normalize_keys_to_strings(story)
  defp unwrap_story!(%{Story: %{} = story}, _path), do: normalize_keys_to_strings(story)

  defp unwrap_story!(%{} = story, path) do
    story = normalize_keys_to_strings(story)

    if is_binary(story["id"]) do
      story
    else
      flunk("unexpected TAPD story payload for #{path}: #{inspect(story)}")
    end
  end

  defp unwrap_story!(payload, path), do: flunk("unexpected TAPD story payload for #{path}: #{inspect(payload)}")

  defp decode_workflow_states!(%{} = data, _path) do
    data
    |> normalize_keys_to_strings()
    |> Map.keys()
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp decode_workflow_states!(data, path), do: flunk("unexpected workflow payload for #{path}: #{inspect(data)}")

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value) when is_binary(value), do: Map.put(params, key, value)

  defp env_value(env_var) when is_binary(env_var) do
    env_var
    |> System.get_env()
    |> normalize_string()
  end

  defp create_template_repo!(template_repo) when is_binary(template_repo) do
    File.mkdir_p!(template_repo)
    File.write!(Path.join(template_repo, "STATUS.txt"), "initial\n")

    cmd_ok!("git", ["-C", template_repo, "init", "-b", "main"])
    cmd_ok!("git", ["-C", template_repo, "config", "user.name", "TAPD Live E2E"])
    cmd_ok!("git", ["-C", template_repo, "config", "user.email", "tapd-live-e2e@example.com"])
    cmd_ok!("git", ["-C", template_repo, "add", "STATUS.txt"])
    cmd_ok!("git", ["-C", template_repo, "commit", "-m", "initial template"])
  end

  defp create_fake_codex_command!(test_root) when is_binary(test_root) do
    codex_binary = Path.join(test_root, "fake-route-policy-codex")

    File.write!(codex_binary, """
    #!/bin/sh
    count=0
    while IFS= read -r line; do
      count=$((count + 1))
      case "$count" in
        1)
          printf '%s\\n' '{"id":1,"result":{}}'
          ;;
        2)
          ;;
        3)
          printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-route-policy-live"}}}'
          ;;
        4)
          printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-route-policy-live"}}}'
          printf '%s\\n' '{"method":"turn/completed"}'
          exit 0
          ;;
        *)
          ;;
      esac
    done
    """)

    File.chmod!(codex_binary, 0o755)
    "#{shell_escape(codex_binary)} app-server"
  end

  defp cmd_ok!(command, args, description \\ nil) when is_binary(command) and is_list(args) do
    case CommandEnv.system_cmd(command, args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        context = if description, do: "#{description}: ", else: ""
        flunk("#{context}command #{command} #{inspect(args)} failed with status #{status}: #{output}")
    end
  end

  defp gh_ok!(args, description) when is_list(args) and is_binary(description) do
    cmd_ok!("gh", args, description)
  end

  defp gh_output!(args, description) when is_list(args) and is_binary(description) do
    case CommandEnv.system_cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        String.trim(output)

      {output, status} ->
        flunk("#{description}: command gh #{inspect(args)} failed with status #{status}: #{output}")
    end
  end

  defp normalize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(nil), do: nil
  defp normalize_string(value), do: to_string(value)

  defp merge_route_policy_runtime_config(runtime_config, route_policy_config)
       when is_map(runtime_config) and is_map(route_policy_config) do
    Map.merge(
      runtime_config,
      Map.take(route_policy_config, [
        :active_states,
        :terminal_states,
        :state_phase_map,
        :raw_state_by_route_key,
        :policy_by_route_key,
        :agent_provider_options
      ])
    )
  end

  defp merge_route_policy_runtime_config(runtime_config, _route_policy_config), do: runtime_config

  defp best_effort_finalize_story(_tracker, nil, _target_state), do: :ok
  defp best_effort_finalize_story(_tracker, _story_id, nil), do: :ok

  defp best_effort_finalize_story(tracker, story_id, target_state) do
    case Client.fetch_stories_by_ids([story_id], tracker: tracker) do
      {:ok, [%Issue{state: ^target_state}]} ->
        :ok

      {:ok, [%Issue{}]} ->
        case Client.update_story_status(story_id, target_state, live_request_opts(tracker: tracker)) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("TAPD live e2e cleanup failed for story_id=#{story_id}: #{inspect(reason)}")
            :ok
        end

      {:ok, _issues} ->
        :ok

      {:error, reason} ->
        Logger.warning("TAPD live e2e cleanup fetch failed for story_id=#{story_id}: #{inspect(reason)}")
        :ok
    end
  end

  defp create_probe_workspace!(workspace_root) when is_binary(workspace_root) do
    workspace = Path.join(workspace_root, "__app_server_probe__")
    File.mkdir_p!(workspace)
    workspace
  end

  defp after_create_hook(%{github_pr: nil, source_repo: %{clone_url: clone_url, base_branch: base_branch}})
       when is_binary(clone_url) and is_binary(base_branch) do
    "mkdir -p repo\n" <>
      "git clone --depth 1 --branch #{shell_escape(base_branch)} #{shell_escape(clone_url)} repo\n" <>
      "git -C repo config user.name 'TAPD Live E2E'\n" <>
      "git -C repo config user.email 'tapd-live-e2e@example.com'"
  end

  defp after_create_hook(%{github_pr: nil, template_repo: template_repo}) when is_binary(template_repo) do
    "mkdir -p repo\n" <>
      "git clone --depth 1 #{shell_escape(template_repo)} repo\n" <>
      "git -C repo config user.name 'TAPD Live E2E'\n" <>
      "git -C repo config user.email 'tapd-live-e2e@example.com'"
  end

  defp after_create_hook(%{github_pr: %{base_branch: base_branch, branch_name: branch_name, clone_url: clone_url}}) do
    "mkdir -p repo\n" <>
      "git clone --depth 1 --branch #{shell_escape(base_branch)} #{shell_escape(clone_url)} repo\n" <>
      "git -C repo config user.name 'TAPD Live E2E'\n" <>
      "git -C repo config user.email 'tapd-live-e2e@example.com'\n" <>
      "git -C repo switch -c #{shell_escape(branch_name)}"
  end

  defp tapd_live_prompt(workspace_id, target_state, run_id, github_pr)
       when is_binary(workspace_id) and is_binary(target_state) and is_binary(run_id) do
    result_template =
      [
        "identifier={{ issue.identifier }}",
        "workspace_id=#{workspace_id}",
        "target_state=#{target_state}",
        "branch_name=<current repo git branch>",
        "commit_sha=<current repo git HEAD short sha>",
        "pr_url=<GitHub PR URL or not-created>",
        "pr_state=<OPEN|MERGED|not-created>"
      ]
      |> maybe_append_previous_pr(github_pr)
      |> maybe_append_rework_action(github_pr)
      |> Enum.join("\n")

    handoff_steps =
      case github_pr do
        %{flow: :pr, base_branch: base_branch, label: label} ->
          """
          Step 8:
          Call inventory capability `repo.push` / runtime tool `repo_push` to push
          the current `repo/` branch to origin. Use the provider-facing callable
          name from the generated inventory and pass `set_upstream: true`.

          Step 9:
          Call inventory capability `repo.create_or_update_change_proposal` /
          runtime tool `repo_create_or_update_change_proposal` to create or
          update a GitHub PR targeting `#{base_branch}` with title
          `tapd live e2e: {{ issue.identifier }}`#{label_requirement_clause(label)}.
          Use mode `upsert`, base `#{base_branch}`, head equal to the current
          `repo/` branch, and omit `body` so Symphony generates the deterministic
          default body.#{label_tool_arguments(label)}
          Then call inventory capability `repo.change_proposal_snapshot` /
          runtime tool `repo_change_proposal_snapshot` to confirm the PR URL and
          state. Do not use `repo-provider`, `gh`, or raw GitHub APIs for this PR
          create/update step.

          Step 10:
          Move the current Story to status `#{target_state}` with `tapd_move_issue`.

          Step 11:
          Read the Story again with `tapd_issue_snapshot`
          and confirm the returned status is exactly `#{target_state}`.

          Step 12:
          Update `.symphony-tapd-workpad.md` in place so completed `Plan`, `Acceptance Criteria`,
          and `Validation` checklist items are checked, `Validation` records `git -C repo diff --check (pass)`,
          and `Notes` records the actual `repo/` branch name, short commit SHA, the GitHub PR URL,
          and `pr_state: OPEN`.

          Step 13:
          Update the existing TAPD workpad comment in place with `tapd_upsert_workpad` so its body
          exactly matches the final `.symphony-tapd-workpad.md` contents.

          Step 14:
          Create a file named #{@result_file} in the current working directory with exactly:

          ```text
          #{result_template}
          ```
          """

        %{flow: :land, base_branch: base_branch, label: label} ->
          """
          Step 8:
          Push the current `repo/` branch to origin.

          Step 9:
          Create or update a GitHub PR targeting `#{base_branch}` with title
          `tapd live e2e: {{ issue.identifier }}`#{label_requirement_clause(label)}.
          If no PR exists for the current branch, use `#{pr_create_command(base_branch, "tapd live e2e: {{ issue.identifier }}")}`.
          If a PR already exists for the current branch, use `#{pr_edit_command("tapd live e2e: {{ issue.identifier }}")}`.
          Use a concrete body; do not leave placeholder text behind.
          #{label_apply_step(label)}

          Step 10:
          Merge the GitHub PR after it is ready.
          Open `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists and follow its land-loop guidance.
          For this temporary live e2e repository, there are no required external checks; after the PR exists#{land_merge_prerequisite(label)}
          and `git -C repo diff --check` has passed, merge it with
          `#{pr_merge_command()}`.
          Confirm the PR state is `MERGED` before continuing.

          Step 11:
          Move the current Story to status `#{target_state}` with `tapd_move_issue`.

          Step 12:
          Read the Story again with `tapd_issue_snapshot`
          and confirm the returned status is exactly `#{target_state}`.

          Step 13:
          Update `.symphony-tapd-workpad.md` in place so completed `Plan`, `Acceptance Criteria`,
          and `Validation` checklist items are checked, `Validation` records `git -C repo diff --check (pass)`,
          and `Notes` records the actual `repo/` branch name, short commit SHA, the GitHub PR URL,
          and `pr_state: MERGED`.

          Step 14:
          Update the existing TAPD workpad comment in place with `tapd_upsert_workpad` so its body
          exactly matches the final `.symphony-tapd-workpad.md` contents.

          Step 15:
          Create a file named #{@result_file} in the current working directory with exactly:

          ```text
          #{result_template}
          ```
          """

        %{
          flow: :rework,
          base_branch: base_branch,
          branch_name: branch_name,
          label: label,
          seed_pr_url: seed_pr_url
        } ->
          """
          Step 8:
          Close the stale PR without merging it: #{seed_pr_url}
          Use `#{pr_close_command(seed_pr_url, "[codex] restarting from a fresh branch for TAPD live e2e")}`.

          Step 9:
          Confirm the current `repo/` branch is a fresh branch from `origin/#{base_branch}` named `#{branch_name}`.
          Create a fresh branch from `origin/#{base_branch}` named `#{branch_name}` if it does not already exist.
          Do not reuse the stale branch.

          Step 10:
          Push the fresh `repo/` branch to origin.

          Step 11:
          Create or update a GitHub PR targeting `#{base_branch}` with title
          `tapd live e2e: {{ issue.identifier }} rework`#{label_requirement_clause(label)}.
          If no PR exists for the current branch, use `#{pr_create_command(base_branch, "tapd live e2e: {{ issue.identifier }} rework")}`.
          If a PR already exists for the current branch, use `#{pr_edit_command("tapd live e2e: {{ issue.identifier }} rework")}`.
          Use a concrete body; do not leave placeholder text behind.
          #{label_apply_step(label)}

          Step 12:
          Move the current Story to status `#{target_state}` with `tapd_move_issue`.

          Step 13:
          Read the Story again with `tapd_issue_snapshot`
          and confirm the returned status is exactly `#{target_state}`.

          Step 14:
          Update `.symphony-tapd-workpad.md` in place so completed `Plan`, `Acceptance Criteria`,
          and `Validation` checklist items are checked, `Validation` records `git -C repo diff --check (pass)`,
          and `Notes` records the actual `repo/` branch name, short commit SHA, the new GitHub PR URL,
          `pr_state: OPEN`, `previous_pr_url: #{seed_pr_url}`, and `rework_action: fresh-branch`.

          Step 15:
          Update the existing TAPD workpad comment in place with `tapd_upsert_workpad` so its body
          exactly matches the final `.symphony-tapd-workpad.md` contents.

          Step 16:
          Create a file named #{@result_file} in the current working directory with exactly:

          ```text
          #{result_template}
          ```
          """

        _ ->
          """
          Step 8:
          Move the current Story to status `#{target_state}` with `tapd_move_issue`.

          Step 9:
          Read the Story again with `tapd_issue_snapshot`
          and confirm the returned status is exactly `#{target_state}`.

          Step 10:
          Update `.symphony-tapd-workpad.md` in place so completed `Plan`, `Acceptance Criteria`,
          and `Validation` checklist items are checked, `Validation` records `git -C repo diff --check (pass)`,
          and `Notes` records the actual `repo/` branch name, short commit SHA, `pr_url: not-created`,
          and `pr_state: not-created`.

          Step 11:
          Update the existing TAPD workpad comment in place with `tapd_upsert_workpad` so its body
          exactly matches the final `.symphony-tapd-workpad.md` contents.

          Step 12:
          Create a file named #{@result_file} in the current working directory with exactly:

          ```text
          #{result_template}
          ```

          Set `pr_url=not-created`.
          Set `pr_state=not-created`.
          """
      end

    """
    You are running a real Symphony TAPD end-to-end test.

    The current working directory is the issue workspace root.
    The target git repository is cloned into `repo/`.

    Generated tool inventory for this session:

    {{ tool_inventory }}

    For every routine tracker, repo-core, or repo-provider action listed in the
    inventory, call the exact provider-facing callable tool name shown in the
    inventory. Runtime tool names such as `tapd_issue_snapshot`, `repo_commit`,
    and `repo_create_or_update_change_proposal` identify the intended Symphony
    tool, but Codex must call the corresponding `mcp__symphony-planned-tools__...`
    callable from the inventory. Do not replace a listed typed capability with
    `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo`, `repo-provider`, `gh`, raw
    REST, or alternate shell/provider APIs.

    Step 1:
    Create a file named `.symphony-tapd-workpad.md` in the issue workspace root with exactly this structure:

    ```md
    ### Plan
    - [ ] 1. Update STATUS.txt
    - [ ] 2. Commit the repository change
    - [ ] 3. Sync TAPD workpad comment
    - [ ] 4. Record handoff details

    ### Acceptance Criteria
    - [ ] `repo/STATUS.txt` records the current Story identifier, full Story id, and target state `#{target_state}`
    - [ ] TAPD workpad comment matches `.symphony-tapd-workpad.md`
    - [ ] Story reread confirms TAPD status `#{target_state}`

    ### Validation
    - [ ] git -C repo diff --check

    ### Notes
    - run_id=#{run_id}
    - branch_name: pending
    - commit_sha: pending
    - pr_url: pending
    - pr_state: pending
    ```

    Step 2:
    Use `tapd_issue_snapshot` to read the current Story by full TAPD Story id `{{ issue.id }}`.

    Step 3:
    Search the snapshot comments/workpad for one comment that contains all of
    `### Plan`, `### Acceptance Criteria`, `### Validation`, and `### Notes`.

    Step 4:
    If a TAPD workpad comment already exists, remember its comment id and update
    `.symphony-tapd-workpad.md` so it matches the current TAPD workpad body before further edits.

    If no TAPD workpad comment exists, create exactly one TAPD workpad comment with
    `tapd_upsert_workpad` whose body is exactly the current `.symphony-tapd-workpad.md`,
    then remember the returned `comment.id` for later updates.

    Step 5:
    Overwrite `repo/STATUS.txt` with exactly:

    ```text
    identifier={{ issue.identifier }}
    story_id={{ issue.id }}
    target_state=#{target_state}
    ```

    Step 6:
    Call inventory capability `repo.diff` / runtime tool `repo_diff` with
    `check: true` and confirm whitespace validation passes.

    Step 7:
    Call inventory capability `repo.commit` / runtime tool `repo_commit` to
    create exactly one git commit in `repo/` with this exact commit subject:
    `tapd live e2e: {{ issue.identifier }}`. Use canonical mode `all`.

    Only `repo/STATUS.txt` should be staged and committed. Do not stage `.symphony-tapd-workpad.md` or #{@result_file}.

    #{handoff_steps}

    Rules:
    - Use only inventory-listed typed tools for routine TAPD, repo-core, and PR actions.
    - Do not call raw TAPD REST APIs, retired TAPD passthrough tools, `repo-provider`, `gh`, or raw GitHub APIs for typed PR actions.
    - Always use the full TAPD API Story id, not the short page id.
    - Keep exactly one active TAPD workpad comment for the Story. Reuse and update it in place instead of creating a second active workpad comment.
    - Do not initialize a new git repository in the workspace root; the target repository is already cloned in `repo/`.
    - Do not ask for approval.
    - Stop only after the workpad file exists, the git commit exists, the TAPD workpad comment exists, the TAPD workpad comment has been updated in place with final handoff state, and the Story status is `#{target_state}`.
    - `.symphony-tapd-workpad.md` must reflect the same final handoff state as the TAPD workpad comment before you stop.
    """
  end

  defp tapd_route_policy_live_prompt(run_id, action)
       when is_binary(run_id) and is_binary(action) do
    """
    TAPD live route-policy smoke for `#{run_id}`.

    Route policy under test: `#{action}`.

    Keep the run minimal:
    - do not call TAPD typed tools
    - do not update Story state
    - do not create or edit TAPD comments
    - create a file named `ROUTE_POLICY_SMOKE.txt` with the single line `action=#{action}`
    """
  end

  defp tapd_live_reuse_prompt(workspace_id, target_state, run_id, comment_id, rerun_token)
       when is_binary(workspace_id) and is_binary(target_state) and is_binary(run_id) and
              is_binary(comment_id) and is_binary(rerun_token) do
    result_template =
      [
        "identifier={{ issue.identifier }}",
        "workspace_id=#{workspace_id}",
        "target_state=#{target_state}",
        "branch_name=<current repo git branch>",
        "commit_sha=<current repo git HEAD short sha>",
        "pr_url=not-created",
        "pr_state=not-created",
        "workpad_comment_id=#{comment_id}",
        "rerun_token=#{rerun_token}"
      ]
      |> Enum.join("\n")

    """
    You are running the second pass of a real Symphony TAPD end-to-end comment reuse test.

    The current working directory is the issue workspace root.
    The target git repository is cloned into `repo/`.

    Generated tool inventory for this session:

    {{ tool_inventory }}

    Use the exact typed tool names from the inventory for TAPD reads and writes.
    Do not guess raw TAPD REST operations or retired TAPD passthrough tools.

    Step 1:
    Use `tapd_issue_snapshot` to read the current Story by full TAPD Story id `{{ issue.id }}`.

    Step 2:
    Find the existing TAPD workpad comment from the snapshot comments/workpad data containing all of
    `### Plan`, `### Acceptance Criteria`, `### Validation`, and `### Notes`.
    It must have id `#{comment_id}`. Do not continue if that exact comment id is missing.

    Step 3:
    Overwrite `.symphony-tapd-workpad.md` so it exactly matches the current TAPD workpad comment body
    before further edits. Preserve the existing `run_id=#{run_id}` note.

    Step 4:
    Overwrite `repo/STATUS.txt` with exactly:

    ```text
    identifier={{ issue.identifier }}
    story_id={{ issue.id }}
    target_state=#{target_state}
    rerun_token=#{rerun_token}
    ```

    Step 5:
    Run `git -C repo diff --check` and confirm it passes.

    Step 6:
    Create exactly one git commit in `repo/` with this exact commit subject:
    `tapd live e2e reuse: {{ issue.identifier }}`

    Only `repo/STATUS.txt` should be staged and committed. Do not stage `.symphony-tapd-workpad.md` or #{@result_file}.

    Step 7:
    Move the current Story to status `#{target_state}` with `tapd_move_issue`.

    Step 8:
    Read the Story again with `tapd_issue_snapshot`
    and confirm the returned status is exactly `#{target_state}`.

    Step 9:
    Update `.symphony-tapd-workpad.md` in place so completed `Plan`, `Acceptance Criteria`,
    and `Validation` checklist items are checked, `Validation` records `git -C repo diff --check (pass)`,
    and `Notes` records the actual `repo/` branch name, short commit SHA, `pr_url: not-created`,
    `pr_state: not-created`, and `rerun_token: #{rerun_token}`.

    Step 10:
    Update the existing TAPD workpad comment in place with `tapd_upsert_workpad` using comment id `#{comment_id}`
    so its body exactly matches the final `.symphony-tapd-workpad.md` contents.
    Do not create a new TAPD comment.

    Step 11:
    Overwrite #{@result_file} in the current working directory with exactly:

    ```text
    #{result_template}
    ```

    Rules:
    - Use only inventory-listed typed TAPD tools for TAPD reads and writes.
    - Do not call raw TAPD REST APIs or retired TAPD passthrough tools.
    - Always use the full TAPD API Story id, not the short page id.
    - Reuse the existing TAPD workpad comment id `#{comment_id}` for all TAPD workpad updates in this run.
    - Do not create a second TAPD workpad comment.
    - Do not initialize a new git repository in the workspace root; the target repository is already cloned in `repo/`.
    - Do not ask for approval.
    - Stop only after the TAPD workpad comment id `#{comment_id}` has been updated in place with the final handoff state, the result file is written, and the Story status is `#{target_state}`.
    """
  end

  defp maybe_append_previous_pr(lines, %{flow: :rework, seed_pr_url: seed_pr_url}) when is_list(lines) do
    lines ++ ["previous_pr_url=#{seed_pr_url}"]
  end

  defp maybe_append_previous_pr(lines, _github_pr), do: lines

  defp maybe_append_rework_action(lines, %{flow: :rework}) when is_list(lines) do
    lines ++ ["rework_action=fresh-branch"]
  end

  defp maybe_append_rework_action(lines, _github_pr), do: lines

  defp label_requirement_clause(label) when is_binary(label), do: " and ensure the GitHub PR has label `#{label}`"
  defp label_requirement_clause(_label), do: ""

  defp label_tool_arguments(label) when is_binary(label),
    do: " Include typed tool argument `labels: [\"#{label}\"]`."

  defp label_tool_arguments(_label), do: ""

  defp pr_create_command(base_branch, title)
       when is_binary(base_branch) and is_binary(title) do
    ~s("${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-create --base #{base_branch} --title "#{title}" --body "<concrete body>")
  end

  defp pr_edit_command(title) when is_binary(title) do
    ~s("${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-edit --title "#{title}" --body "<concrete body>")
  end

  defp pr_close_command(selector, comment)
       when is_binary(selector) and is_binary(comment) do
    ~s("${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-close #{selector} --comment "#{comment}")
  end

  defp pr_merge_command, do: ~s("${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-merge --squash)

  defp label_apply_step(label) when is_binary(label) do
    ~s(After the PR exists, use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-add-label "#{label}"` if the label is not already present.)
  end

  defp label_apply_step(_label), do: "A GitHub PR label is not required for this run."

  defp land_merge_prerequisite(label) when is_binary(label), do: " and has label `#{label}`"
  defp land_merge_prerequisite(_label), do: ""

  defp expected_status_contents(issue_identifier, story_id, target_state) do
    "identifier=#{issue_identifier}\nstory_id=#{story_id}\ntarget_state=#{target_state}\n"
  end

  defp expected_reuse_status_contents(issue_identifier, story_id, target_state, rerun_token) do
    "identifier=#{issue_identifier}\nstory_id=#{story_id}\ntarget_state=#{target_state}\nrerun_token=#{rerun_token}\n"
  end

  defp read_worker_result!(%{worker_host: nil, workspace_path: workspace_path}, result_file)
       when is_binary(workspace_path) and is_binary(result_file) do
    File.read!(Path.join(workspace_path, result_file))
  end

  defp read_worker_file!(%{worker_host: nil, workspace_path: workspace_path}, relative_path)
       when is_binary(workspace_path) and is_binary(relative_path) do
    File.read!(Path.join(workspace_path, relative_path))
  end

  defp read_worker_repo_file!(%{worker_host: nil, workspace_path: workspace_path}, relative_path)
       when is_binary(workspace_path) and is_binary(relative_path) do
    File.read!(Path.join([workspace_path, "repo", relative_path]))
  end

  defp read_git_output!(%{worker_host: nil, workspace_path: workspace_path}, git_args)
       when is_binary(workspace_path) and is_list(git_args) do
    case CommandEnv.system_cmd("git", git_args, cd: Path.join(workspace_path, "repo"), stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        flunk("git #{inspect(git_args)} failed with status #{status}: #{output}")
    end
  end

  defp result_value!(result, key) when is_binary(result) and is_binary(key) do
    case result_value(result, key) do
      nil ->
        flunk("missing #{key} in TAPD live e2e result: #{inspect(result)}")

      value ->
        value
    end
  end

  defp result_value(result, key) when is_binary(result) and is_binary(key) do
    result
    |> String.split("\n", trim: true)
    |> Enum.find(&String.starts_with?(&1, "#{key}="))
    |> case do
      nil -> nil
      line -> String.replace_prefix(line, "#{key}=", "")
    end
  end

  defp fetch_story_comments!(config, story_id) when is_map(config) and is_binary(story_id) do
    case Client.request(
           "GET",
           "/comments",
           %{"entry_type" => "stories", "entry_id" => story_id, "order" => "created asc", "limit" => 100},
           live_request_opts(tracker: config.bootstrap_tracker)
         ) do
      {:ok, body} ->
        case Client.decode_success_envelope("/comments", body) do
          {:ok, data} when is_list(data) ->
            Enum.map(data, &unwrap_comment!/1)

          {:ok, other} ->
            flunk("unexpected TAPD comments payload: #{inspect(other)}")

          {:error, reason} ->
            flunk("failed to decode TAPD comments payload: #{inspect(reason)}")
        end

      {:error, reason} ->
        flunk("failed to fetch TAPD story comments: #{inspect(reason)}")
    end
  end

  defp reopen_story_for_reuse!(config) when is_map(config) do
    reopen_state =
      List.first(config.active_states) ||
        flunk("expected at least one TAPD active state for comment reuse live test")

    assert :ok = Client.update_story_status(config.story_id, reopen_state, live_request_opts(tracker: config.bootstrap_tracker))

    [%Issue{} = reopened_issue] = live_fetch_issue_states_by_ids!([config.story_id])
    assert reopened_issue.state == reopen_state

    candidate_issues = live_fetch_candidate_issues!()
    assert Enum.any?(candidate_issues, &(&1.id == config.story_id))

    reopen_state
  end

  defp unwrap_comment!(%{"Comment" => %{} = comment}), do: stringify_keys(comment)
  defp unwrap_comment!(%{Comment: %{} = comment}), do: stringify_keys(comment)

  defp unwrap_comment!(%{} = comment) do
    normalized_comment = stringify_keys(comment)

    case Map.get(normalized_comment, "id") do
      id when is_binary(id) and id != "" -> normalized_comment
      id when is_integer(id) -> Map.put(normalized_comment, "id", Integer.to_string(id))
      _ -> flunk("unexpected TAPD comment payload: #{inspect(comment)}")
    end
  end

  defp unwrap_comment!(entry), do: flunk("unexpected TAPD comment entry: #{inspect(entry)}")

  defp comment_body_from_api!(comments, comment_id)
       when is_list(comments) and (is_binary(comment_id) or is_integer(comment_id)) do
    normalized_id = to_string(comment_id)

    Enum.find_value(comments, fn comment ->
      if Map.get(comment, "id") == normalized_id, do: Map.get(comment, "description")
    end) || flunk("expected TAPD comment #{inspect(normalized_id)} in #{inspect(comments)}")
  end

  defp normalize_multiline(value) when is_binary(value) do
    value
    |> String.replace("\r\n", "\n")
    |> String.trim()
  end

  defp workpad_comment?(%{"description" => description}) when is_binary(description) do
    Enum.all?(
      ["### Plan", "### Acceptance Criteria", "### Validation", "### Notes"],
      &String.contains?(description, &1)
    )
  end

  defp workpad_comment?(_comment), do: false

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp collect_run_messages!(issue_id) do
    case collect_run_messages(issue_id, nil, []) do
      {nil, _messages} ->
        flunk("timed out waiting for worker runtime info for #{inspect(issue_id)}")

      {runtime_info, messages} ->
        {runtime_info, messages}
    end
  end

  defp collect_run_messages(issue_id, runtime_info, acc) do
    receive do
      {:worker_runtime_info, ^issue_id, %{workspace_path: workspace_path} = message_runtime_info}
      when is_binary(workspace_path) ->
        collect_run_messages(issue_id, message_runtime_info, acc)

      {:agent_worker_update, ^issue_id, message} ->
        collect_run_messages(issue_id, runtime_info, [message | acc])
    after
      1_000 ->
        {runtime_info, Enum.reverse(acc)}
    end
  end

  defp assert_dynamic_tool_succeeded!(config, tool) when is_map(config) and is_binary(tool) do
    events = dynamic_tool_events(config)

    Enum.find(events, fn event ->
      event["event"] == "tool_call_succeeded" and
        event["tool_name"] == tool and
        event["dynamic_tool_usage_kind"] == "typed"
    end) ||
      flunk("expected typed #{tool} success in #{inspect(dynamic_tool_event_summary(events))}")
  end

  defp refute_retired_raw_tools_called!(config) when is_map(config) do
    events = dynamic_tool_events(config)

    retired_events =
      Enum.filter(events, fn event ->
        event["tool_name"] in ["linear_graphql", "tapd_api"]
      end)

    assert retired_events == []
  end

  defp dynamic_tool_events(%{run_id: run_id}) when is_binary(run_id) do
    %{run_id: run_id}
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

  defp github_pull_request!(pr_url) when is_binary(pr_url) do
    case CommandEnv.system_cmd("gh", ["pr", "view", pr_url, "--json", "url,state,headRefName,baseRefName,labels"], stderr_to_stdout: true) do
      {output, 0} ->
        Jason.decode!(output)

      {output, status} ->
        flunk("failed to inspect GitHub PR #{inspect(pr_url)}: status=#{status} output=#{output}")
    end
  end

  defp assert_github_flow!(%{flow: :pr}, pr_info, _result, _branch_name) do
    assert pr_info["state"] == "OPEN"
  end

  defp assert_github_flow!(%{flow: :land} = github_pr, pr_info, result, _branch_name) do
    assert pr_info["state"] == "MERGED"
    assert result_value!(result, "pr_state") == "MERGED"
    assert remote_file_contents!(github_pr, "STATUS.txt") =~ "target_state="
  end

  defp assert_github_flow!(%{flow: :rework} = github_pr, pr_info, result, branch_name) do
    assert pr_info["state"] == "OPEN"
    assert result_value!(result, "pr_state") == "OPEN"
    assert result_value!(result, "previous_pr_url") == github_pr.seed_pr_url
    assert result_value!(result, "rework_action") == "fresh-branch"
    assert branch_name == github_pr.branch_name

    stale_pr_info = github_pull_request!(github_pr.seed_pr_url)
    assert stale_pr_info["state"] == "CLOSED"
    assert stale_pr_info["headRefName"] == github_pr.seed_branch_name
  end

  defp assert_git_subject!(runtime_info, %{flow: :land}, issue_identifier) when is_binary(issue_identifier) do
    assert read_git_output!(runtime_info, ["log", "-1", "--pretty=%s"]) =~
             "tapd live e2e: #{issue_identifier}"
  end

  defp assert_git_subject!(runtime_info, _github_pr, issue_identifier) when is_binary(issue_identifier) do
    assert read_git_output!(runtime_info, ["log", "-1", "--pretty=%s"]) ==
             "tapd live e2e: #{issue_identifier}\n"
  end

  defp expected_pr_head_ref(%{flow: :land, branch_name: branch_name}, _current_branch)
       when is_binary(branch_name),
       do: branch_name

  defp expected_pr_head_ref(_github_pr, current_branch), do: current_branch

  defp cleanup_extra_pr_urls(%{flow: :rework, seed_pr_url: seed_pr_url}), do: [seed_pr_url]
  defp cleanup_extra_pr_urls(_github_pr), do: []

  defp prepare_live_orchestrator_issue!(config, prompt, expected_state)
       when is_map(config) and is_binary(prompt) and is_binary(expected_state) do
    write_live_workflow!(config, prompt)
    force_story_state!(config, expected_state)

    [%Issue{} = refreshed_issue] = live_fetch_issue_states_by_ids!([config.story_id])
    assert refreshed_issue.id == config.story_id
    assert refreshed_issue.state == expected_state

    candidate_issues = live_fetch_candidate_issues!()

    Enum.find(candidate_issues, &(&1.id == config.story_id)) ||
      flunk("expected TAPD live story #{inspect(config.story_id)} in candidate issues: #{inspect(candidate_issues)}")
  end

  defp force_story_state!(config, target_state)
       when is_map(config) and is_binary(target_state) do
    assert :ok =
             Client.update_story_status(config.story_id, target_state, live_request_opts(tracker: config.bootstrap_tracker))

    [%Issue{} = refreshed_issue] = live_fetch_issue_states_by_ids!([config.story_id])
    assert refreshed_issue.state == target_state
    :ok
  end

  defp live_request_opts(opts) when is_list(opts) do
    Keyword.put_new(opts, :retry_delays_ms, @live_retry_delays_ms)
  end

  defp live_fetch_candidate_issues! do
    case retry_live_tapd_request(&Tracker.fetch_candidate_issues/0) do
      {:ok, issues} when is_list(issues) ->
        issues

      {:error, reason} ->
        flunk("failed to fetch TAPD candidate issues during live smoke: #{inspect(reason)}")
    end
  end

  defp live_fetch_issue_states_by_ids!(issue_ids) when is_list(issue_ids) do
    case retry_live_tapd_request(fn -> Tracker.fetch_issue_states_by_ids(issue_ids) end) do
      {:ok, issues} when is_list(issues) ->
        issues

      {:error, reason} ->
        flunk("failed to fetch TAPD issue states during live smoke: #{inspect(reason)}")
    end
  end

  defp retry_live_tapd_request(fun, retry_delays_ms \\ @live_retry_delays_ms)
       when is_function(fun, 0) and is_list(retry_delays_ms) do
    case fun.() do
      {:ok, _value} = ok ->
        ok

      {:error, reason} = error ->
        case {live_retryable_tapd_error?(reason), retry_delays_ms} do
          {true, [delay_ms | remaining_retry_delays_ms]} ->
            Process.sleep(delay_ms)
            retry_live_tapd_request(fun, remaining_retry_delays_ms)

          _ ->
            error
        end
    end
  end

  defp live_retryable_tapd_error?({:tapd_http_status, status, _body})
       when status in [408, 429, 500, 502, 503, 504],
       do: true

  defp live_retryable_tapd_error?({:tapd_workflow_lookup_failed, _workitem_type_id, _type, reason}),
    do: live_retryable_tapd_error?(reason)

  defp live_retryable_tapd_error?({:tapd_request, _reason}), do: true
  defp live_retryable_tapd_error?(_reason), do: false

  defp run_live_orchestrator_poll_cycle! do
    {:ok, initial_state} = Orchestrator.init([])
    cancel_tick_timer(initial_state)
    test_pid = self()

    log =
      capture_log([level: :debug], fn ->
        assert {:noreply, returned_state} = Orchestrator.handle_info(:run_poll_cycle, initial_state)
        send(test_pid, {:live_orchestrator_poll_cycle, returned_state})
      end)

    assert_receive {:live_orchestrator_poll_cycle, returned_state}
    cancel_tick_timer(returned_state)
    {returned_state, log}
  end

  defp cancel_tick_timer(%{tick_timer_ref: tick_timer_ref}) when is_reference(tick_timer_ref) do
    Process.cancel_timer(tick_timer_ref)
    :ok
  end

  defp cancel_tick_timer(_state), do: :ok

  defp stop_running_entry(%{pid: pid, ref: ref}) do
    if is_pid(pid) and Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    if is_reference(ref) do
      Process.demonitor(ref, [:flush])
    end

    :ok
  end

  defp stop_running_entry(_running_entry), do: :ok

  defp flush_orchestrator_test_messages do
    receive do
      {:DOWN, _ref, :process, _pid, _reason} ->
        flush_orchestrator_test_messages()

      {:tick, _tick_token} ->
        flush_orchestrator_test_messages()

      :run_poll_cycle ->
        flush_orchestrator_test_messages()
    after
      0 ->
        :ok
    end
  end

  defp raw_state!(config, route_key) when is_map(config) and is_atom(route_key) do
    raw_state_by_route_key = Map.get(config, :raw_state_by_route_key, %{})

    Map.get(raw_state_by_route_key, Atom.to_string(route_key)) ||
      Map.get(raw_state_by_route_key, route_key) ||
      flunk("missing TAPD raw state for route key #{inspect(route_key)} in #{inspect(raw_state_by_route_key)}")
  end

  defp route_phase_name(:planning), do: "todo"
  defp route_phase_name(:developing), do: "in_progress"
  defp route_phase_name(:review), do: "human_review"
  defp route_phase_name(:merging), do: "merging"
  defp route_phase_name(:rework), do: "rework"
  defp route_phase_name(:resolved), do: "done"
  defp route_phase_name(:rejected), do: "canceled"

  defp remote_file_contents!(github_pr, path) when is_map(github_pr) and is_binary(path) do
    checkout_dir = Path.join(System.tmp_dir!(), "symphony-tapd-live-remote-read-#{System.unique_integer([:positive])}")

    try do
      cmd_ok!(
        "git",
        ["clone", "--depth", "1", "--branch", github_pr.base_branch, github_pr.clone_url, checkout_dir],
        "clone temporary GitHub smoke repository for remote file read"
      )

      File.read!(Path.join(checkout_dir, path))
    after
      File.rm_rf(checkout_dir)
    end
  end

  defp best_effort_cleanup_github_pr(nil, _cleanup), do: :ok

  defp best_effort_cleanup_github_pr(%{branch_name: branch_name} = github_pr, nil) do
    github_pr
    |> cleanup_extra_pr_urls()
    |> Enum.each(&best_effort_close_github_pr/1)

    case best_effort_open_pr_url_for_branch(branch_name) do
      nil -> best_effort_delete_remote_branch(github_pr, github_pr.branch_name)
      pr_url -> best_effort_cleanup_github_pr(github_pr, %{pr_url: pr_url})
    end
  end

  defp best_effort_cleanup_github_pr(%{branch_name: branch_name} = github_pr, cleanup) when is_map(cleanup) do
    pr_url =
      cleanup
      |> Map.get(:pr_url)
      |> normalize_string()

    cleanup
    |> Map.get(:extra_pr_urls, [])
    |> List.wrap()
    |> Enum.each(&best_effort_close_github_pr/1)

    if is_binary(pr_url) and pr_url != "not-created" do
      best_effort_close_github_pr(pr_url, branch_name, github_pr)
    else
      best_effort_delete_remote_branch(github_pr, branch_name)
    end
  end

  defp best_effort_close_github_pr(nil), do: :ok
  defp best_effort_close_github_pr(pr_url) when is_binary(pr_url), do: best_effort_close_github_pr(pr_url, nil)

  defp best_effort_close_github_pr(pr_url, branch_name) when is_binary(pr_url) do
    best_effort_close_github_pr(pr_url, branch_name, nil)
  end

  defp best_effort_close_github_pr(pr_url, branch_name, github_pr) when is_binary(pr_url) do
    case CommandEnv.system_cmd("gh", ["pr", "close", pr_url, "--delete-branch", "--comment", "[codex] closing TAPD live e2e smoke PR"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Logger.warning("TAPD live e2e PR cleanup failed for #{inspect(pr_url)}: status=#{status} output=#{output}")

        if is_binary(branch_name) do
          best_effort_delete_remote_branch(github_pr, branch_name)
        else
          :ok
        end
    end
  end

  defp best_effort_cleanup_github_repo(%{temporary_repo?: true, repo_name_with_owner: repo_name_with_owner}) do
    best_effort_delete_github_repo(repo_name_with_owner)
  end

  defp best_effort_cleanup_github_repo(_github_pr), do: :ok

  defp best_effort_delete_github_repo(repo_name_with_owner) when is_binary(repo_name_with_owner) do
    case CommandEnv.system_cmd("gh", ["repo", "delete", repo_name_with_owner, "--yes"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Logger.warning("TAPD live e2e temporary repo cleanup failed for #{repo_name_with_owner}: status=#{status} output=#{output}")
        :ok
    end
  end

  defp best_effort_open_pr_url_for_branch(branch_name) when is_binary(branch_name) do
    case CommandEnv.system_cmd("gh", ["pr", "list", "--head", branch_name, "--state", "open", "--json", "url", "--jq", ".[0].url // \"\""], stderr_to_stdout: true) do
      {output, 0} ->
        normalize_string(output)

      {_output, _status} ->
        nil
    end
  end

  defp best_effort_delete_remote_branch(github_pr, branch_name) when is_binary(branch_name) do
    git_root = git_repo_root!()
    remote = if is_map(github_pr) and is_binary(github_pr[:clone_url]), do: github_pr.clone_url, else: "origin"

    case CommandEnv.system_cmd("git", ["push", remote, "--delete", branch_name], cd: git_root, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Logger.warning("TAPD live e2e remote branch cleanup failed for #{inspect(branch_name)}: status=#{status} output=#{output}")
        :ok
    end
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp restart_orchestrator_if_needed do
    if is_nil(Process.whereis(SymphonyElixir.Orchestrator)) do
      case bounded_orchestrator_restart() do
        :ok -> :ok
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, {:timeout, _details}} -> wait_for_orchestrator_restart()
        {:error, :restarting} -> wait_for_orchestrator_restart()
      end
    end
  end

  defp bounded_orchestrator_restart(timeout_ms \\ 5_000)
       when is_integer(timeout_ms) and timeout_ms > 0 do
    task =
      Task.async(fn ->
        restart_supervised_child(SymphonyElixir.Orchestrator)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        Logger.warning("TAPD live e2e cleanup timed out while waiting for orchestrator restart")
        {:error, {:timeout, :restart_child}}
    end
  end

  defp wait_for_orchestrator_restart(deadline_ms \\ 5_000) when is_integer(deadline_ms) and deadline_ms >= 0 do
    started_at_ms = System.monotonic_time(:millisecond)
    do_wait_for_orchestrator_restart(started_at_ms, deadline_ms)
  end

  defp do_wait_for_orchestrator_restart(started_at_ms, deadline_ms)
       when is_integer(started_at_ms) and is_integer(deadline_ms) do
    case Process.whereis(SymphonyElixir.Orchestrator) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms

        if elapsed_ms >= deadline_ms do
          Logger.warning("TAPD live e2e cleanup could not confirm orchestrator restart before timeout")
          :ok
        else
          Process.sleep(100)
          do_wait_for_orchestrator_restart(started_at_ms, deadline_ms)
        end
    end
  end
end
