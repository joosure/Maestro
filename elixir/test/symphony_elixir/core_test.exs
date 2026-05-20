defmodule SymphonyElixir.CoreTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Orchestrator.Running
  alias SymphonyElixir.Orchestrator.Runtime, as: OrchestratorRuntime
  alias SymphonyElixir.Orchestrator.ServerOptions
  alias SymphonyElixir.Orchestrator.WorkerHosts
  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.RepoProvider.Error, as: RepoProviderError
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Error, as: TrackerError

  defmodule FailingLinearClient do
    def fetch_candidate_issues(_tracker) do
      send(self(), :failing_linear_fetch_candidate_issues_called)
      {:error, :candidate_fetch_failed_in_test}
    end

    def fetch_issues_by_states(_states, _tracker), do: {:ok, []}
    def fetch_issue_states_by_ids(_issue_ids, _tracker), do: {:ok, []}
    def graphql(_query, _variables, _opts), do: {:error, :unexpected_graphql_call}
  end

  defp bundled_workflow_template_path(criteria) when is_map(criteria) do
    SymphonyElixir.Workflow.Templates.paths()
    |> Enum.find_value(fn path ->
      case Workflow.load(path) do
        {:ok, %{config: config}} ->
          if workflow_template_matches?(config, criteria), do: path

        {:error, _reason} ->
          nil
      end
    end) ||
      flunk("no bundled workflow template matched #{inspect(criteria)}")
  end

  defp tapd_github_codex_workflow_template_path do
    bundled_workflow_template_path(%{
      tracker: "tapd",
      repo_provider: "github",
      agent_provider: "codex"
    })
  end

  defp tapd_cnb_claude_code_workflow_template_path do
    bundled_workflow_template_path(%{
      tracker: "tapd",
      repo_provider: "cnb",
      agent_provider: "claude_code"
    })
  end

  defp tapd_cnb_codebuddy_code_workflow_template_path do
    bundled_workflow_template_path(%{
      tracker: "tapd",
      repo_provider: "cnb",
      agent_provider: "codebuddy_code"
    })
  end

  defp linear_github_claude_code_workflow_template_path do
    bundled_workflow_template_path(%{
      tracker: "linear",
      repo_provider: "github",
      agent_provider: "claude_code"
    })
  end

  defp linear_tracker_skill_path do
    Path.expand("../../priv/workspace_automation/skills/tracker/linear/SKILL.md", __DIR__)
  end

  defp workflow_template_matches?(config, criteria) when is_map(config) and is_map(criteria) do
    Enum.all?(criteria, fn
      {:tracker, expected} -> get_in(config, ["tracker", "kind"]) == expected
      {:repo_provider, expected} -> get_in(config, ["repo", "provider", "kind"]) == expected
      {:agent_provider, expected} -> get_in(config, ["agent_provider", "kind"]) == expected
    end)
  end

  test "config defaults and validation checks" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: nil,
      tracker_project_slug: nil,
      poll_interval_ms: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      agent_provider_options: %{}
    )

    config = Config.settings!()
    assert config.polling.interval_ms == 30_000
    assert TrackerConfig.active_states(config.tracker) == ["Todo", "In Progress"]

    assert TrackerConfig.terminal_states(config.tracker) == [
             "Closed",
             "Cancelled",
             "Canceled",
             "Duplicate",
             "Done"
           ]

    assert TrackerConfig.state_phase_map(config.tracker)["todo"] == "todo"
    assert TrackerConfig.state_phase_map(config.tracker)["in progress"] == "in_progress"
    assert TrackerConfig.state_phase_map(config.tracker)["done"] == "done"
    assert TrackerConfig.provider(config.tracker)["assignee"] == nil
    assert config.agent.execution.max_turns == 20

    assert config.repo.path == "repo"
    assert config.repo.remote.name == "origin"
    assert config.repo.remote.url == nil

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_path: "$SOURCE_REPO_PATH",
      repo_remote_name: "$SOURCE_REPO_REMOTE",
      repo_remote_url: "$SOURCE_REPO_URL"
    )

    previous_repo_path = System.get_env("SOURCE_REPO_PATH")
    previous_repo_remote = System.get_env("SOURCE_REPO_REMOTE")
    previous_repo_url = System.get_env("SOURCE_REPO_URL")

    try do
      System.put_env("SOURCE_REPO_PATH", "target-repo")
      System.put_env("SOURCE_REPO_REMOTE", "upstream")
      System.put_env("SOURCE_REPO_URL", "https://example.test/acme/widgets.git")

      config = Config.settings!()
      assert config.repo.path == "target-repo"
      assert config.repo.remote.name == "upstream"
      assert config.repo.remote.url == "https://example.test/acme/widgets.git"
    after
      restore_env("SOURCE_REPO_PATH", previous_repo_path)
      restore_env("SOURCE_REPO_REMOTE", previous_repo_remote)
      restore_env("SOURCE_REPO_URL", previous_repo_url)
    end

    write_workflow_file!(Workflow.workflow_file_path(), poll_interval_ms: "invalid")

    assert_raise ArgumentError, ~r/interval_ms/, fn ->
      Config.settings!().polling.interval_ms
    end

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "polling.interval_ms"

    write_workflow_file!(Workflow.workflow_file_path(), poll_interval_ms: 45_000)
    assert Config.settings!().polling.interval_ms == 45_000

    write_workflow_file!(Workflow.workflow_file_path(), max_turns: 0)
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent.execution.max_turns"

    write_workflow_file!(Workflow.workflow_file_path(), max_turns: 5)
    assert Config.settings!().agent.execution.max_turns == 5

    write_workflow_file!(Workflow.workflow_file_path(), tracker_active_states: "Todo,  Review,")
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.lifecycle.active_states"

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: "token",
      tracker_project_slug: nil
    )

    assert {:error,
            %TrackerError{
              provider: "linear",
              operation: :validate_config,
              code: :missing_project_reference,
              details: %{source_reason: :missing_linear_project_slug}
            }} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_project_slug: "project",
      agent_provider_options: %{command: ""}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "command"
    assert message =~ "can't be blank"

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{command: "   "})
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "command"
    assert message =~ "can't be blank"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{command: "/bin/sh app-server"}
    )

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{approval_policy: "definitely-not-valid"}
    )

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{thread_sandbox: "unsafe-ish"}
    )

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{
        turn_sandbox_policy: %{type: "workspaceWrite", writableRoots: ["relative/path"]}
      }
    )

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{approval_policy: 123}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "approval_policy"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{thread_sandbox: 123}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "thread_sandbox"

    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "123")
    assert {:error, {:unsupported_tracker_kind, "123"}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_project_slug: "project",
      agent_provider_options: %{command: "/bin/sh app-server"},
      repo_provider_kind: "gitlab"
    )

    assert {:error,
            %RepoProviderError{
              code: :unsupported_provider,
              provider: "gitlab",
              operation: :validate_config
            }} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_project_slug: "project",
      agent_provider_options: %{command: "/bin/sh app-server"},
      repo_provider_kind: "cnb",
      repo_provider_required_pr_label: "release-ready"
    )

    assert {:error,
            %RepoProviderError{
              code: :unsupported_option,
              provider: "cnb",
              operation: :validate_config
            }} =
             Config.validate!()

    workflow_path = Workflow.workflow_file_path()

    File.write!(
      workflow_path,
      """
      ---
      tracker:
        kind: linear
        api_key: token
        project_slug: project
        active_states: ["Todo", "In Progress"]
        terminal_states: ["Done"]
        state_phase_map: {"Todo": "todo", "In Progress": "in_progress", "Done": "done"}
      polling:
        interval_ms: 30000
      workspace:
        root: "#{Path.join(System.tmp_dir!(), "symphony_workspaces")}"
        bootstrap_automation_from: null
      worker:
        ssh_hosts: []
      repo:
        base_branch: "main"
        required_pr_label: "release-ready"
        provider:
          kind: github
          repository: null
          api_base_url: null
          web_base_url: null
          options:
            required_pr_label: null
      agent:
        execution:
          max_concurrent_agents: 10
          max_turns: 20
          max_retry_backoff_ms: 300000
          max_concurrent_agents_by_state: {}
      agent_provider:
        kind: "codex"
        options:
          command: "codex app-server"
          approval_policy: {"reject": {"sandbox_approval": true, "rules": true, "mcp_elicitations": true}}
          thread_sandbox: "workspace-write"
          turn_sandbox_policy: null
          turn_timeout_ms: 3600000
          read_timeout_ms: 5000
          stall_timeout_ms: 300000
      hooks:
        timeout_ms: 60000
      observability:
        dashboard_enabled: true
        refresh_ms: 1000
        render_interval_ms: 16
        file_enabled: true
        console_enabled: false
        log_format: "json"
        summary_max_bytes: 512
        global_event_limit: 1000
        issue_event_limit: 50
        run_event_limit: 200
        session_event_limit: 200
        index_key_limit: 500
      ---
      Workflow prompt.
      """
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "has been removed"
    assert message =~ "use repo.provider.options.required_pr_label instead"
  end

  test "current WORKFLOW.md file is valid and complete" do
    original_workflow_path = Workflow.workflow_file_path()
    on_exit(fn -> Workflow.set_workflow_file_path(original_workflow_path) end)
    Workflow.clear_workflow_file_path()

    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load()
    assert is_map(config)

    assert get_in(config, ["workflow", "profile", "kind"]) == "coding_pr_delivery"
    assert get_in(config, ["workflow", "profile", "options", "requirements", "typed_tracker_tools"]) == true
    assert get_in(config, ["workflow", "profile", "options", "requirements", "typed_repo_tools"]) == true

    tracker = Map.get(config, "tracker", %{})
    assert is_map(tracker)
    assert Map.get(tracker, "kind") == "linear"
    assert get_in(tracker, ["provider", "project_slug"]) == "$LINEAR_PROJECT_SLUG"
    assert is_list(get_in(tracker, ["lifecycle", "active_states"]))
    assert is_list(get_in(tracker, ["lifecycle", "terminal_states"]))
    assert get_in(tracker, ["lifecycle", "state_phase_map", "In Review"]) == "human_review"

    workspace = Map.get(config, "workspace", %{})
    assert is_map(workspace)
    assert Map.get(workspace, "root") == "$SYMPHONY_WORKSPACE_ROOT"
    assert Map.get(workspace, "bootstrap_automation_from") == nil

    repo = Map.get(config, "repo", %{})
    assert is_map(repo)
    assert Map.get(repo, "path") == "repo"
    assert Map.get(repo, "base_branch") == "$SOURCE_REPO_BASE_BRANCH"

    assert Map.get(repo, "remote") == %{
             "name" => "origin",
             "url" => "$SOURCE_REPO_URL"
           }

    assert Map.get(repo, "provider") == %{
             "kind" => "github",
             "repository" => "$SOURCE_REPO_PROVIDER_REPOSITORY",
             "api_base_url" => nil,
             "web_base_url" => nil,
             "options" => %{
               "required_pr_label" => "$SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL"
             }
           }

    hooks = Map.get(config, "hooks", %{})
    assert is_map(hooks)

    assert Map.get(hooks, "after_create") =~
             "\"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo\" clone"

    assert Map.get(hooks, "after_create") =~ "--depth 1"
    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_BASE_BRANCH"
    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_URL"
    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_URL is required"
    assert Map.get(hooks, "after_create") =~ " repo"
    assert Map.get(hooks, "after_create") =~ "Optional: add target-repo bootstrap here"
    refute Map.get(hooks, "after_create") =~ "git clone"
    refute Map.get(hooks, "after_create") =~ "symphony.git"
    refute Map.get(hooks, "after_create") =~ "repo/elixir"
    assert Map.get(hooks, "before_remove") =~ "Optional: add target-repo cleanup here"
    refute Map.get(hooks, "before_remove") =~ "repo/elixir"

    assert get_in(config, ["agent_provider", "options", "command"]) =~ "project_root_markers=[]"

    assert String.trim(prompt) != ""
    assert is_binary(Config.workflow_prompt())
    assert Config.workflow_prompt() == prompt
    assert prompt =~ "provided repository copy at `repo/`"

    assert prompt =~
             "The active repo provider for bundled automation is `{{ repo.provider.kind }}`."

    assert prompt =~ "When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` exists"
    assert prompt =~ "provider-neutral repo facts"

    assert prompt =~ "`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` exists"

    assert prompt =~
             "workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists"

    assert prompt =~ "{{ tool_inventory }}"
    assert prompt =~ "Linear Access Boundary"
    assert prompt =~ "Use the inventory `tracker.move_issue` typed tool"
    assert prompt =~ "Fetch the issue by explicit ticket ID through the inventory `tracker.issue_snapshot` typed tool"
    assert prompt =~ "Use the inventory `tracker.issue_snapshot` typed tool with comments included"
    assert prompt =~ "through the inventory `tracker.upsert_workpad` typed tool"
    assert prompt =~ "Record a short note in the workpad if state and issue content are inconsistent"
    assert prompt =~ "tracker.attach_change_proposal"
    assert prompt =~ "If it is missing, stop as blocked and record the missing typed tracker capability"
    assert prompt =~ "repo.read_change_proposal_discussion"
    assert prompt =~ "unresolvedFeedbackSummary.unresolvedItems"
    assert prompt =~ "repo.read_change_proposal_checks"
    assert prompt =~ "repo.create_or_update_change_proposal"
    assert prompt =~ "repo.change_proposal_snapshot"
    assert prompt =~ "Create or update the PR through the inventory `repo.create_or_update_change_proposal` typed tool"
    assert prompt =~ "For a new PR, pass `mode: \"create\"`, `title`, `base: \"{{ repo.base_branch }}\"`"
    assert prompt =~ "Confirm the resulting PR with `repo.change_proposal_snapshot`"
    assert prompt =~ "`repo.commit` mode is `all` or `staged`"
    assert prompt =~ "`repo.checkout` mode is `create_or_switch`, `create`, or `switch`"
    assert prompt =~ "supported branch, diff, commit, and push actions"
    assert prompt =~ "except for the workflow state transition described below"
    assert prompt =~ "repo-core helper"
    refute prompt =~ "active repo-provider tooling"
    refute prompt =~ "pr-add-label"
    refute prompt =~ "repo-provider pr-issue-comments"
    refute prompt =~ "repo-provider pr-reviews"
    refute prompt =~ "repo-provider pr-review-comments"
    refute prompt =~ "Add a short comment if state and issue content are inconsistent"
    refute prompt =~ "update_issue("
    refute prompt =~ "Human Review"
  end

  test "bundled TAPD GitHub Codex workflow template is valid and reusable for arbitrary repos" do
    original_workflow_path = Workflow.workflow_file_path()
    on_exit(fn -> Workflow.set_workflow_file_path(original_workflow_path) end)
    Workflow.set_workflow_file_path(tapd_github_codex_workflow_template_path())

    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load()
    assert is_map(config)

    tracker = Map.get(config, "tracker", %{})
    assert is_map(tracker)
    assert Map.get(tracker, "kind") == "tapd"
    assert is_list(get_in(tracker, ["lifecycle", "active_states"]))
    assert is_list(get_in(tracker, ["lifecycle", "terminal_states"]))

    workspace = Map.get(config, "workspace", %{})
    assert is_map(workspace)
    assert Map.get(workspace, "bootstrap_automation_from") == nil

    repo = Map.get(config, "repo", %{})
    assert is_map(repo)
    assert Map.get(repo, "path") == "repo"
    assert Map.get(repo, "base_branch") == "$SOURCE_REPO_BASE_BRANCH"

    assert Map.get(repo, "remote") == %{
             "name" => "origin",
             "url" => "$SOURCE_REPO_URL"
           }

    hooks = Map.get(config, "hooks", %{})
    assert is_map(hooks)

    assert Map.get(hooks, "after_create") =~
             "\"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo\" clone"

    assert Map.get(hooks, "after_create") =~ "--depth 1"
    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_BASE_BRANCH"
    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_URL"
    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_URL is required"
    assert Map.get(hooks, "after_create") =~ " repo"
    assert Map.get(hooks, "after_create") =~ "Optional: add target-repo bootstrap here"
    refute Map.get(hooks, "after_create") =~ "git clone"
    refute Map.get(hooks, "after_create") =~ "symphony.git"
    refute Map.get(hooks, "after_create") =~ "repo/elixir"
    assert Map.get(hooks, "before_remove") =~ "Optional: add target-repo cleanup here"
    refute Map.get(hooks, "before_remove") =~ "repo/elixir"

    assert get_in(config, ["agent_provider", "options", "command"]) =~ "project_root_markers=[]"

    assert prompt =~ "provided repository copy at `repo/`"

    assert prompt =~
             "The active repo provider for bundled automation is `{{ repo.provider.kind }}`."

    assert prompt =~ "When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` exists"
    assert prompt =~ "provider-neutral repo operations not"

    assert prompt =~ "`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` exists"

    assert prompt =~
             "workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists"

    assert prompt =~
             "Otherwise, merge the PR with the repository's normal repo-core/repo-provider flow"

    refute prompt =~ "For sample-repo, set `SOURCE_REPO_URL=https://github.com/example-user/sample-repo.git`"
    refute prompt =~ "make e2e-tapd"

    assert prompt =~ "{% if repo.provider.kind == \"github\" %}"
    assert prompt =~ "{% if repo.provider.options.required_pr_label %}"
    assert prompt =~ "Ensure the PR has label `{{ repo.provider.options.required_pr_label }}`."
    assert prompt =~ "labels: [\"{{ repo.provider.options.required_pr_label }}\"]"
    refute prompt =~ "pr-add-label"
    assert prompt =~ "actionableItems"
    assert prompt =~ "unresolvedFeedbackSummary"
    assert prompt =~ "responseAction"
    assert prompt =~ "prefilledArguments"
    assert prompt =~ "requiredArguments"
    assert prompt =~ "repo_add_change_proposal_comment"
    assert prompt =~ "repo_reply_change_proposal_review_comment"
    refute prompt =~ "repo-provider pr-issue-comments"
    refute prompt =~ "repo-provider pr-reviews"
    refute prompt =~ "repo-provider pr-review-comments"
  end

  test "bundled TAPD CNB Claude Code workflow template is valid for full-flow validation" do
    original_workflow_path = Workflow.workflow_file_path()

    env_overrides = %{
      "TAPD_API_USER" => "tapd-user",
      "TAPD_API_PASSWORD" => "tapd-password",
      "TAPD_WORKSPACE_ID" => "123456",
      "SOURCE_REPO_URL" => "https://cnb.cool/acme/widgets",
      "SOURCE_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
      "SOURCE_REPO_BASE_BRANCH" => "main",
      "CNB_TOKEN" => "test-cnb-token"
    }

    previous_env = Map.new(env_overrides, fn {key, _value} -> {key, System.get_env(key)} end)

    on_exit(fn ->
      Workflow.set_workflow_file_path(original_workflow_path)
      Enum.each(previous_env, fn {key, value} -> restore_env(key, value) end)
    end)

    Enum.each(env_overrides, fn {key, value} -> System.put_env(key, value) end)
    Workflow.set_workflow_file_path(tapd_cnb_claude_code_workflow_template_path())

    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load()
    assert :ok = Config.validate!()

    assert get_in(config, ["tracker", "kind"]) == "tapd"
    assert get_in(config, ["repo", "provider", "kind"]) == "cnb"

    assert get_in(config, ["repo", "provider", "repository"]) ==
             "$SOURCE_REPO_PROVIDER_REPOSITORY"

    assert get_in(config, ["repo", "provider", "options", "required_pr_label"]) == nil

    hooks = Map.get(config, "hooks", %{})
    assert Map.get(hooks, "after_create") =~ "CNB_TOKEN is required"
    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_URL must be an HTTP(S) CNB clone URL"
    assert Map.get(hooks, "after_create") =~ ".extraHeader=Authorization: Basic"

    assert Map.get(hooks, "after_create") =~
             "git -C repo config \"http.${cnb_auth_scope}.extraHeader\""

    assert Map.get(hooks, "after_create") =~ "git -C repo config user.name"

    assert get_in(config, ["agent_provider", "kind"]) == "claude_code"
    assert get_in(config, ["agent_provider", "options", "command_argv"]) == ["claude"]
    assert get_in(config, ["agent_provider", "options", "prompt_transport"]) == "stream_json"
    assert get_in(config, ["agent_provider", "options", "permission_mode"]) == "bypassPermissions"
    assert get_in(config, ["agent_provider", "options", "model"]) == "sonnet"

    assert prompt =~ "## CNB Provider Notes"
    assert prompt =~ "SOURCE_REPO_PROVIDER_REPOSITORY"
    assert prompt =~ "owner/group/repo"
    assert prompt =~ "Use the inventory `repo.create_or_update_change_proposal` typed tool"
    assert prompt =~ "Pass `mode`, `base`, `head`, and `title`"
    assert prompt =~ "omit `body` when no task-specific body is needed"
    assert prompt =~ "repo.change_proposal_snapshot"
    assert prompt =~ "use it only as documented fallback"
    assert prompt =~ "/-/pulls/"
    assert prompt =~ "Do not use `--target-branch`, `--description`, `curl`, `gh`, `glab`, `brew`"
    refute prompt =~ "repo-provider\" pr-create"
    refute prompt =~ "repo-provider\" pr-view --json"
  end

  test "bundled TAPD CNB CodeBuddy Code workflow template is valid for full-flow validation" do
    original_workflow_path = Workflow.workflow_file_path()

    env_overrides = %{
      "TAPD_API_USER" => "tapd-user",
      "TAPD_API_PASSWORD" => "tapd-password",
      "TAPD_WORKSPACE_ID" => "123456",
      "SOURCE_REPO_URL" => "https://cnb.cool/acme/widgets",
      "SOURCE_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
      "SOURCE_REPO_BASE_BRANCH" => "main",
      "CNB_TOKEN" => "test-cnb-token"
    }

    previous_env = Map.new(env_overrides, fn {key, _value} -> {key, System.get_env(key)} end)

    on_exit(fn ->
      Workflow.set_workflow_file_path(original_workflow_path)
      Enum.each(previous_env, fn {key, value} -> restore_env(key, value) end)
    end)

    Enum.each(env_overrides, fn {key, value} -> System.put_env(key, value) end)
    Workflow.set_workflow_file_path(tapd_cnb_codebuddy_code_workflow_template_path())

    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load()
    assert :ok = Config.validate!()

    assert get_in(config, ["tracker", "kind"]) == "tapd"
    assert get_in(config, ["repo", "provider", "kind"]) == "cnb"

    assert get_in(config, ["agent", "credentials", "enabled"]) == true
    assert get_in(config, ["agent", "quota", "preflight"]) == "off"

    assert get_in(config, ["agent_provider", "kind"]) == "codebuddy_code"
    assert get_in(config, ["agent_provider", "options", "transport"]) == "acp_stdio"
    assert get_in(config, ["agent_provider", "options", "command_argv"]) == ["codebuddy"]
    assert get_in(config, ["agent_provider", "options", "credential_ref"]) == "credential://codebuddy_code/default"
    assert get_in(config, ["agent_provider", "options", "permission_mode"]) == "bypass_permissions"
    assert get_in(config, ["agent_provider", "options", "mcp", "enabled"]) == true
    assert get_in(config, ["agent_provider", "options", "plugin", "enabled"]) == false
    assert get_in(config, ["agent_provider", "options", "http", "enabled"]) == false

    assert prompt =~ "## Provider Runtime: CodeBuddy Code MCP Dynamic-Tool Bridge"
    assert prompt =~ "session-scoped MCP"
    assert prompt =~ "repository-authored CodeBuddy plugins"
    assert prompt =~ "provider-specific callable names"
    assert prompt =~ "## CNB Provider Notes"
    assert prompt =~ "Use the inventory `repo.create_or_update_change_proposal` typed tool"
    refute prompt =~ "The Open Code CLI"
    refute prompt =~ "opencode"
  end

  test "bundled Linear GitHub Claude Code workflow template is valid for full-flow validation" do
    original_workflow_path = Workflow.workflow_file_path()

    env_overrides = %{
      "LINEAR_API_KEY" => "linear-test-api-key",
      "LINEAR_PROJECT_SLUG" => "example-project",
      "SOURCE_REPO_URL" => "https://github.com/example-user/sample-repo.git",
      "SOURCE_REPO_PROVIDER_REPOSITORY" => "example-user/sample-repo",
      "SOURCE_REPO_BASE_BRANCH" => "main",
      "SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL" => "ready-for-agent"
    }

    previous_env = Map.new(env_overrides, fn {key, _value} -> {key, System.get_env(key)} end)

    on_exit(fn ->
      Workflow.set_workflow_file_path(original_workflow_path)
      Enum.each(previous_env, fn {key, value} -> restore_env(key, value) end)
    end)

    Enum.each(env_overrides, fn {key, value} -> System.put_env(key, value) end)
    Workflow.set_workflow_file_path(linear_github_claude_code_workflow_template_path())

    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load()
    assert :ok = Config.validate!()

    settings = Config.settings!()

    assert TrackerConfig.api_key(settings.tracker) == "linear-test-api-key"
    assert TrackerConfig.provider(settings.tracker)["project_slug"] == "example-project"

    assert get_in(config, ["tracker", "kind"]) == "linear"
    assert get_in(config, ["repo", "provider", "kind"]) == "github"

    assert get_in(config, ["repo", "provider", "repository"]) ==
             "$SOURCE_REPO_PROVIDER_REPOSITORY"

    assert get_in(config, ["repo", "provider", "options", "required_pr_label"]) ==
             "$SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL"

    hooks = Map.get(config, "hooks", %{})

    assert Map.get(hooks, "after_create") =~
             "\"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo\" clone"

    assert Map.get(hooks, "after_create") =~ "SOURCE_REPO_URL is required"
    assert Map.get(hooks, "after_create") =~ "Optional: add target-repo bootstrap here"
    assert Map.get(hooks, "before_remove") =~ "Optional: add target-repo cleanup here"

    assert get_in(config, ["agent_provider", "kind"]) == "claude_code"
    assert get_in(config, ["agent_provider", "options", "command_argv"]) == ["claude"]
    assert get_in(config, ["agent_provider", "options", "prompt_transport"]) == "stream_json"
    assert get_in(config, ["agent_provider", "options", "permission_mode"]) == "bypassPermissions"
    assert get_in(config, ["agent_provider", "options", "model"]) == "sonnet"

    assert get_in(config, ["workflow", "profile", "options", "requirements", "typed_tracker_tools"]) ==
             true

    assert get_in(config, ["workflow", "profile", "options", "requirements", "typed_repo_tools"]) == true

    assert prompt =~
             "The active repo provider for bundled automation is `{{ repo.provider.kind }}`."

    assert prompt =~ "When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` exists"

    assert prompt =~
             "\"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo\" diff-check \"origin/{{ repo.base_branch }}...HEAD\""

    assert prompt =~ "Do not substitute plain `git diff --check` on a clean working tree"

    assert prompt =~
             "When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` exists"

    assert prompt =~
             "workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists"

    assert prompt =~ "## Claude Code Workpad"
    assert prompt =~ "## Provider Runtime: Claude Code MCP dynamic-tool bridge"

    assert prompt =~
             "Claude Code receives Symphony Dynamic Tools through the MCP dynamic-tool bridge"

    assert prompt =~ "This is a Claude Code provider runtime"
    assert prompt =~ "prerequisite whenever this session exposes Dynamic Tools"
    assert prompt =~ "it is not a\nLinear/GitHub workflow prerequisite"
    assert prompt =~ "repo-provider change-proposal actions"
    assert prompt =~ "{{ tool_inventory }}"
    assert prompt =~ "For Linear tracker actions, open and follow the bundled workspace skill"
    assert prompt =~ "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/linear/SKILL.md"
    assert prompt =~ "provider-facing callable tool names listed in the generated inventory"
    assert prompt =~ "tracker.attach_change_proposal"

    assert prompt =~
             "The inventory is the only source for Claude Code's provider-specific callable"

    refute prompt =~ "`mcp__symphony-planned-tools__...`"

    assert prompt =~ "Linear Access Boundary"
    assert prompt =~ "Only use inventory-listed typed Linear tools"
    assert prompt =~ "typed tracker tools and treat missing typed capabilities as blockers"

    assert prompt =~ "For repo-core or repo-provider operations covered by the inventory, use the"
    assert prompt =~ "typed tool."
    assert prompt =~ "correct the typed tool arguments and retry that same typed tool"
    assert prompt =~ "Do not switch\n"
    assert prompt =~ "non-inventory Linear or repo access path"
    assert prompt =~ "do not use any non-inventory Linear access path"
    refute prompt =~ "branchName"
    refute prompt =~ "Raw Linear GraphQL"
    refute prompt =~ "raw Linear GraphQL"
    refute prompt =~ "states(filter: {name: {eq: $stateName}}, first: 1)"
    refute prompt =~ "issueUpdate(id: $issueId, input: {stateId: $stateId})"
    refute prompt =~ "commentUpdate(id: $id, input: {body: $body})"
    refute prompt =~ "attachmentLinkGitHubPR"
    refute prompt =~ "branches {"
    refute prompt =~ "resolved\n"

    linear_skill = File.read!(linear_tracker_skill_path())
    assert linear_skill =~ "This skill owns Linear tracker semantics"
    assert linear_skill =~ "Workflow templates own when those actions are"
    assert linear_skill =~ "Linear Access Boundary"
    assert linear_skill =~ "Only use inventory-listed typed Linear tools"
    assert linear_skill =~ "`tracker.issue_snapshot`"
    assert linear_skill =~ "`tracker.upsert_comment`"
    assert linear_skill =~ "`tracker.prepare_file_upload`"
    refute linear_skill =~ "Raw Linear GraphQL"
    refute linear_skill =~ "raw GraphQL"
    refute linear_skill =~ "query IssueTeamStates($id: String!)"
    refute linear_skill =~ "issueUpdate(id: $id, input: { stateId: $stateId })"
    refute linear_skill =~ "commentUpdate(id: $id, input: { body: $body })"
    refute linear_skill =~ "attachmentLinkGitHubPR"

    assert prompt =~
             "Otherwise, use the inventory `repo.merge_change_proposal` typed tool when it is listed"

    assert prompt =~ "{% if repo.provider.kind == \"github\" %}"
    assert prompt =~ "{% if repo.provider.options.required_pr_label %}"
    assert prompt =~ "Ensure the PR has label `{{ repo.provider.options.required_pr_label }}`"
    assert prompt =~ "repo.read_change_proposal_discussion"
    assert prompt =~ "unresolvedFeedbackSummary"
    assert prompt =~ "responseAction"
    assert prompt =~ "prefilledArguments"
    assert prompt =~ "requiredArguments"
    assert prompt =~ "repo.add_change_proposal_comment"
    assert prompt =~ "repo.reply_change_proposal_review_comment"
    assert prompt =~ "repo.read_change_proposal_checks"
    assert prompt =~ "If a required feedback capability is missing from the inventory"
    refute prompt =~ "repo-provider pr-issue-comments"
    refute prompt =~ "repo-provider pr-reviews"
    refute prompt =~ "repo-provider pr-review-comments"
  end

  test "linear api token resolves from LINEAR_API_KEY env var" do
    previous_linear_api_key = System.get_env("LINEAR_API_KEY")
    env_api_key = "test-linear-api-key"

    on_exit(fn -> restore_env("LINEAR_API_KEY", previous_linear_api_key) end)
    System.put_env("LINEAR_API_KEY", env_api_key)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: nil,
      tracker_project_slug: "project",
      agent_provider_options: %{command: "/bin/sh app-server"}
    )

    assert TrackerConfig.api_key(Config.settings!().tracker) == env_api_key
    assert TrackerConfig.provider(Config.settings!().tracker)["project_slug"] == "project"
    assert :ok = Config.validate!()
  end

  test "linear assignee resolves from LINEAR_ASSIGNEE env var" do
    previous_linear_assignee = System.get_env("LINEAR_ASSIGNEE")
    env_assignee = "dev@example.com"

    on_exit(fn -> restore_env("LINEAR_ASSIGNEE", previous_linear_assignee) end)
    System.put_env("LINEAR_ASSIGNEE", env_assignee)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_assignee: nil,
      tracker_project_slug: "project",
      agent_provider_options: %{command: "/bin/sh app-server"}
    )

    assert TrackerConfig.provider(Config.settings!().tracker)["assignee"] == env_assignee
  end

  test "workflow file path defaults to WORKFLOW.md in the current working directory when app env is unset" do
    original_workflow_path = Workflow.workflow_file_path()

    on_exit(fn ->
      Workflow.set_workflow_file_path(original_workflow_path)
    end)

    Workflow.clear_workflow_file_path()

    assert Workflow.workflow_file_path() == Path.join(File.cwd!(), "WORKFLOW.md")
  end

  test "workflow file path resolves from app env when set" do
    app_workflow_path = "/tmp/app/WORKFLOW.md"

    on_exit(fn ->
      Workflow.clear_workflow_file_path()
    end)

    Workflow.set_workflow_file_path(app_workflow_path)

    assert Workflow.workflow_file_path() == app_workflow_path
  end

  test "workflow load accepts prompt-only files without front matter" do
    workflow_path =
      Path.join(Path.dirname(Workflow.workflow_file_path()), "PROMPT_ONLY_WORKFLOW.md")

    File.write!(workflow_path, "Prompt only\n")

    assert {:ok, %{config: %{}, prompt: "Prompt only", prompt_template: "Prompt only"}} =
             Workflow.load(workflow_path)
  end

  test "workflow load accepts unterminated front matter with an empty prompt" do
    workflow_path =
      Path.join(Path.dirname(Workflow.workflow_file_path()), "UNTERMINATED_WORKFLOW.md")

    File.write!(workflow_path, "---\ntracker:\n  kind: linear\n")

    assert {:ok, %{config: %{"tracker" => %{"kind" => "linear"}}, prompt: "", prompt_template: ""}} =
             Workflow.load(workflow_path)
  end

  test "workflow load rejects non-map front matter" do
    workflow_path =
      Path.join(Path.dirname(Workflow.workflow_file_path()), "INVALID_FRONT_MATTER_WORKFLOW.md")

    File.write!(workflow_path, "---\n- not-a-map\n---\nPrompt body\n")

    assert {:error, :workflow_front_matter_not_a_map} = Workflow.load(workflow_path)
  end

  test "SymphonyElixir.start_link delegates to the orchestrator" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
    Application.put_env(:symphony_elixir, :memory_tracker_issues, [])
    orchestrator_pid = Process.whereis(SymphonyElixir.Orchestrator)

    on_exit(fn ->
      if is_nil(Process.whereis(SymphonyElixir.Orchestrator)) do
        assert :ok = restart_supervised_child(SymphonyElixir.Orchestrator)
      end
    end)

    if is_pid(orchestrator_pid) do
      assert :ok = terminate_supervised_child(SymphonyElixir.Orchestrator)
    end

    assert {:ok, pid} = SymphonyElixir.start_link()
    assert Process.whereis(SymphonyElixir.Orchestrator) == pid

    GenServer.stop(pid)
  end

  test "application stop emits a structured service lifecycle event" do
    log =
      capture_log(fn ->
        assert :ok = SymphonyElixir.Application.stop(:ok)
      end)

    assert log =~ "service_stopped"
  end

  test "orchestrator poll cycle emits structured skip events for blocked issues" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")

    issue = %Issue{
      id: "issue-blocked-dispatch",
      identifier: "MT-BLOCKED",
      title: "Blocked work",
      description: "Should be skipped during dispatch",
      state: "Todo",
      blocked_by: [%{state: "In Progress"}]
    }

    Application.put_env(:symphony_elixir, :memory_tracker_issues, [issue])

    orchestrator_name = __MODULE__.BlockedDispatchOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :memory_tracker_issues)

      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    state = :sys.get_state(pid)

    log =
      capture_log([level: :debug], fn ->
        assert {:noreply, started_state} = Orchestrator.handle_info(:tick, state)

        assert {:noreply, _returned_state} =
                 Orchestrator.handle_info(:run_poll_cycle, started_state)
      end)

    assert log =~ "poll_cycle_started"
    assert log =~ "issue_dispatch_skipped"
    assert log =~ "reason=blocked"
    assert log =~ "poll_cycle_completed"
  end

  test "orchestrator emits structured selected and started events when dispatching an issue" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-dispatch-events-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(test_root)

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
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-dispatch"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-dispatch"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-dispatch-events",
        identifier: "MT-DISPATCH",
        title: "Dispatch event coverage",
        description: "Emit selected and started events",
        state: "In Progress"
      }

      Application.put_env(:symphony_elixir, :memory_tracker_issues, [issue])

      orchestrator_name = __MODULE__.DispatchEventsOrchestrator
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        Application.delete_env(:symphony_elixir, :memory_tracker_issues)

        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      state = :sys.get_state(pid)

      test_pid = self()

      log =
        capture_log(fn ->
          assert {:noreply, returned_state} = Orchestrator.handle_info(:run_poll_cycle, state)
          send(test_pid, {:dispatch_returned_state, returned_state})
        end)

      assert_receive {:dispatch_returned_state, returned_state}

      assert log =~ "issue_dispatch_selected"
      assert log =~ "issue_dispatch_started"
      assert log =~ "workflow_profile=coding_pr_delivery"
      assert log =~ "workflow_route_key=developing"
      assert log =~ "workflow_route_action=dispatch"
      assert log =~ "workflow_gate_status=open"
      assert log =~ "workflow_gate=dispatch"
      assert log =~ "poll_cycle_completed"

      running_entry = Map.fetch!(returned_state.running, issue.id)

      if is_pid(running_entry.pid) and Process.alive?(running_entry.pid) do
        Process.exit(running_entry.pid, :kill)
      end
    after
      File.rm_rf(test_root)
    end
  end

  test "orchestrator emits structured tracker candidate fetch failures during poll cycles" do
    previous_linear_client_module = Application.get_env(:symphony_elixir, :linear_client_module)
    Application.put_env(:symphony_elixir, :linear_client_module, FailingLinearClient)

    orchestrator_name = __MODULE__.TrackerCandidateFetchFailureOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if is_nil(previous_linear_client_module) do
        Application.delete_env(:symphony_elixir, :linear_client_module)
      else
        Application.put_env(
          :symphony_elixir,
          :linear_client_module,
          previous_linear_client_module
        )
      end

      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    state = :sys.get_state(pid)

    log =
      capture_log(fn ->
        assert {:noreply, returned_state} = Orchestrator.handle_info(:run_poll_cycle, state)
        send(self(), {:tracker_candidate_fetch_failure_state, returned_state})
      end)

    assert_receive :failing_linear_fetch_candidate_issues_called
    assert_receive {:tracker_candidate_fetch_failure_state, _returned_state}
    assert log =~ "tracker_candidate_fetch_failed"
    assert log =~ "candidate_fetch_failed_in_test"
    assert log =~ "poll_cycle_completed"
  end

  test "linear issue state reconciliation fetch with no running issues is a no-op" do
    assert {:ok, []} = Client.fetch_issue_states_by_ids([], TrackerConfig.current!())
  end

  test "stale non-active issue state stops running agent without cleaning workspace" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-nonactive-reconcile-#{System.unique_integer([:positive])}"
      )

    issue_id = "issue-1"
    issue_identifier = "MT-555"
    workspace = Path.join(test_root, issue_identifier)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: test_root,
        tracker_active_states: ["Todo", "In Progress", "In Review"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate"]
      )

      File.mkdir_p!(test_root)
      File.mkdir_p!(workspace)

      agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      state = %Orchestrator.State{
        running: %{
          issue_id => %{
            pid: agent_pid,
            ref: nil,
            identifier: issue_identifier,
            issue: %Issue{id: issue_id, state: "Todo", identifier: issue_identifier},
            started_at: DateTime.add(DateTime.utc_now(), -40, :second)
          }
        },
        claimed: MapSet.new([issue_id]),
        agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
        retry_attempts: %{}
      }

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Backlog",
        title: "Queued",
        description: "Not started",
        labels: []
      }

      log =
        capture_log(fn ->
          send(self(), {:updated_state, reconcile_issue_states([issue], state)})
        end)

      assert_receive {:updated_state, updated_state}

      refute Map.has_key?(updated_state.running, issue_id)
      refute MapSet.member?(updated_state.claimed, issue_id)
      refute Process.alive?(agent_pid)
      assert File.exists?(workspace)
      assert log =~ "issue_reconcile_stopped"
      assert log =~ "skip_reason=not_active"
    after
      File.rm_rf(test_root)
    end
  end

  test "terminal issue state stops running agent and cleans workspace" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-terminal-reconcile-#{System.unique_integer([:positive])}"
      )

    issue_id = "issue-2"
    issue_identifier = "MT-556"
    workspace = Path.join(test_root, issue_identifier)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: test_root,
        tracker_active_states: ["Todo", "In Progress", "In Review"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate"]
      )

      File.mkdir_p!(test_root)
      File.mkdir_p!(workspace)

      agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      state = %Orchestrator.State{
        running: %{
          issue_id => %{
            pid: agent_pid,
            ref: nil,
            identifier: issue_identifier,
            issue: %Issue{id: issue_id, state: "In Progress", identifier: issue_identifier},
            started_at: DateTime.utc_now()
          }
        },
        claimed: MapSet.new([issue_id]),
        agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
        retry_attempts: %{}
      }

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Closed",
        title: "Done",
        description: "Completed",
        labels: []
      }

      log =
        capture_log(fn ->
          send(self(), {:terminal_updated_state, reconcile_issue_states([issue], state)})
        end)

      assert_receive {:terminal_updated_state, updated_state}

      refute Map.has_key?(updated_state.running, issue_id)
      refute MapSet.member?(updated_state.claimed, issue_id)
      refute Process.alive?(agent_pid)
      refute File.exists?(workspace)
      assert log =~ "issue_reconcile_stopped"
      assert log =~ "issue_workspace_cleanup_requested"
    after
      File.rm_rf(test_root)
    end
  end

  test "terminal cleanup uses the recorded workspace path even after workflow root changes" do
    original_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-terminal-recorded-cleanup-original-#{System.unique_integer([:positive])}"
      )

    current_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-terminal-recorded-cleanup-current-#{System.unique_integer([:positive])}"
      )

    issue_id = "issue-terminal-recorded-cleanup"
    issue_identifier = "MT-RECORDED-CLEANUP"
    workspace = Path.join(original_root, issue_identifier)

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: original_root,
        tracker_active_states: ["Todo", "In Progress", "In Review"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate"]
      )

      File.mkdir_p!(workspace)

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: current_root,
        tracker_active_states: ["Todo", "In Progress", "In Review"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate"]
      )

      agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      state = %Orchestrator.State{
        running: %{
          issue_id => %{
            pid: agent_pid,
            ref: nil,
            identifier: issue_identifier,
            issue: %Issue{id: issue_id, state: "In Progress", identifier: issue_identifier},
            workspace_path: workspace,
            started_at: DateTime.utc_now()
          }
        },
        claimed: MapSet.new([issue_id]),
        agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
        retry_attempts: %{}
      }

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Closed",
        title: "Done",
        description: "Completed",
        labels: []
      }

      log =
        capture_log(fn ->
          send(
            self(),
            {:terminal_recorded_cleanup_state, reconcile_issue_states([issue], state)}
          )
        end)

      assert_receive {:terminal_recorded_cleanup_state, updated_state}

      refute Map.has_key?(updated_state.running, issue_id)
      refute MapSet.member?(updated_state.claimed, issue_id)
      refute Process.alive?(agent_pid)
      refute File.exists?(workspace)
      assert log =~ "issue_workspace_cleanup_requested"
      assert log =~ workspace
    after
      File.rm_rf(original_root)
      File.rm_rf(current_root)
    end
  end

  test "missing running issues stop active agents without cleaning the workspace" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-missing-running-reconcile-#{System.unique_integer([:positive])}"
      )

    previous_memory_issues = Application.get_env(:symphony_elixir, :memory_tracker_issues)
    issue_id = "issue-missing"
    issue_identifier = "MT-557"

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: test_root,
        tracker_active_states: ["Todo", "In Progress", "In Review"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate"],
        poll_interval_ms: 30_000
      )

      Application.put_env(:symphony_elixir, :memory_tracker_issues, [])

      orchestrator_name = __MODULE__.MissingRunningIssueOrchestrator
      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        restore_app_env(:memory_tracker_issues, previous_memory_issues)

        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      Process.sleep(50)

      assert {:ok, workspace} =
               SymphonyElixir.PathSafety.canonicalize(Path.join(test_root, issue_identifier))

      File.mkdir_p!(workspace)

      agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      initial_state = :sys.get_state(pid)

      running_entry = %{
        pid: agent_pid,
        ref: nil,
        identifier: issue_identifier,
        issue: %Issue{id: issue_id, state: "In Progress", identifier: issue_identifier},
        started_at: DateTime.utc_now()
      }

      :sys.replace_state(pid, fn _ ->
        initial_state
        |> Map.put(:running, %{issue_id => running_entry})
        |> Map.put(:claimed, MapSet.new([issue_id]))
        |> Map.put(:retry_attempts, %{})
      end)

      log =
        capture_log(fn ->
          send(pid, :tick)
          Process.sleep(100)
        end)

      state = :sys.get_state(pid)

      refute Map.has_key?(state.running, issue_id)
      refute MapSet.member?(state.claimed, issue_id)
      refute Process.alive?(agent_pid)
      assert File.exists?(workspace)
      assert log =~ "issue_reconcile_stopped"
      assert log =~ "skip_reason=missing_visible"
    after
      restore_app_env(:memory_tracker_issues, previous_memory_issues)
      File.rm_rf(test_root)
    end
  end

  test "reconcile updates running issue state for active issues" do
    issue_id = "issue-3"

    state = %Orchestrator.State{
      running: %{
        issue_id => %{
          pid: self(),
          ref: nil,
          identifier: "MT-557",
          issue: %Issue{
            id: issue_id,
            identifier: "MT-557",
            state: "Todo"
          },
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue_id]),
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: issue_id,
      identifier: "MT-557",
      state: "In Progress",
      title: "Active state refresh",
      description: "State should be refreshed",
      labels: []
    }

    updated_state = reconcile_issue_states([issue], state)
    updated_entry = updated_state.running[issue_id]

    assert Map.has_key?(updated_state.running, issue_id)
    assert MapSet.member?(updated_state.claimed, issue_id)
    assert updated_entry.issue.state == "In Progress"
  end

  test "reconcile stops running issue when it is reassigned away from this worker" do
    issue_id = "issue-reassigned"

    agent_pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    state = %Orchestrator.State{
      running: %{
        issue_id => %{
          pid: agent_pid,
          ref: nil,
          identifier: "MT-561",
          issue: %Issue{
            id: issue_id,
            identifier: "MT-561",
            state: "In Progress",
            assigned_to_worker: true
          },
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue_id]),
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: issue_id,
      identifier: "MT-561",
      state: "In Progress",
      title: "Reassigned active issue",
      description: "Worker should stop",
      labels: [],
      assigned_to_worker: false
    }

    updated_state = reconcile_issue_states([issue], state)

    refute Map.has_key?(updated_state.running, issue_id)
    refute MapSet.member?(updated_state.claimed, issue_id)
    refute Process.alive?(agent_pid)
  end

  test "normal worker exit schedules active-state continuation retry" do
    issue_id = "issue-resume"
    ref = make_ref()
    orchestrator_name = __MODULE__.ContinuationOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name, schedule_initial_poll?: false)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-558",
      issue: %Issue{id: issue_id, identifier: "MT-558", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> Map.put(:retry_attempts, %{})
    end)

    scheduled_from_ms = System.monotonic_time(:millisecond)

    log =
      capture_log(fn ->
        send(pid, {:DOWN, ref, :process, self(), :normal})
        Process.sleep(50)
      end)

    state = :sys.get_state(pid)

    refute Map.has_key?(state.running, issue_id)
    assert MapSet.member?(state.completed, issue_id)
    assert %{attempt: 1, due_at_ms: due_at_ms} = state.retry_attempts[issue_id]
    assert is_integer(due_at_ms)
    assert due_at_ms >= scheduled_from_ms + 900
    assert due_at_ms <= scheduled_from_ms + 2_500
    assert log =~ "issue_worker_finished"
    assert log =~ "status=completed"
    assert log =~ "result=continuation_scheduled"
    assert log =~ "issue_retry_scheduled"
  end

  test "abnormal worker exit increments retry attempt progressively" do
    issue_id = "issue-crash"
    ref = make_ref()
    orchestrator_name = __MODULE__.CrashRetryOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name, schedule_initial_poll?: false)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-559",
      retry_attempt: 2,
      issue: %Issue{id: issue_id, identifier: "MT-559", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> Map.put(:retry_attempts, %{})
    end)

    send(pid, {:DOWN, ref, :process, self(), :boom})
    Process.sleep(50)
    state = :sys.get_state(pid)

    assert %{attempt: 3, due_at_ms: due_at_ms, identifier: "MT-559", error: "agent exited: :boom"} =
             state.retry_attempts[issue_id]

    assert_due_in_range(due_at_ms, 35_000, 40_500)
  end

  test "first abnormal worker exit waits before retrying" do
    issue_id = "issue-crash-initial"
    ref = make_ref()
    orchestrator_name = __MODULE__.InitialCrashRetryOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name, schedule_initial_poll?: false)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-560",
      issue: %Issue{id: issue_id, identifier: "MT-560", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> Map.put(:retry_attempts, %{})
    end)

    log =
      capture_log(fn ->
        send(pid, {:DOWN, ref, :process, self(), :boom})
        Process.sleep(50)
      end)

    state = :sys.get_state(pid)

    assert %{attempt: 1, due_at_ms: due_at_ms, identifier: "MT-560", error: "agent exited: :boom"} =
             state.retry_attempts[issue_id]

    assert_due_in_range(due_at_ms, 5_000, 10_500)
    assert log =~ "issue_worker_finished"
    assert log =~ "status=exited"
    assert log =~ "result=retry_scheduled"
    assert log =~ "reason=:boom"
    assert log =~ "issue_retry_scheduled"
    assert log =~ "agent_run_retry_scheduled"
  end

  test "abnormal worker exit preserves failure_class in the retry entry" do
    issue_id = "issue-crash-failure-class"
    ref = make_ref()
    orchestrator_name = __MODULE__.FailureClassRetryOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name, schedule_initial_poll?: false)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: ref,
      identifier: "MT-561",
      failure_class: "remote_startup_failure",
      issue: %Issue{id: issue_id, identifier: "MT-561", state: "In Progress"},
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> Map.put(:retry_attempts, %{})
    end)

    send(pid, {:DOWN, ref, :process, self(), :boom})
    Process.sleep(50)
    state = :sys.get_state(pid)

    assert %{attempt: 1, failure_class: "remote_startup_failure"} = state.retry_attempts[issue_id]
  end

  test "stale retry timer messages do not consume newer retry entries" do
    issue_id = "issue-stale-retry"
    orchestrator_name = __MODULE__.StaleRetryOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name, schedule_initial_poll?: false)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    current_retry_token = make_ref()
    stale_retry_token = make_ref()

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:retry_attempts, %{
        issue_id => %{
          attempt: 2,
          timer_ref: nil,
          retry_token: current_retry_token,
          due_at_ms: System.monotonic_time(:millisecond) + 30_000,
          identifier: "MT-561",
          error: "agent exited: :boom"
        }
      })
    end)

    log =
      capture_log(fn ->
        send(pid, {:retry_issue, issue_id, stale_retry_token})
        Process.sleep(50)
      end)

    assert %{
             attempt: 2,
             retry_token: ^current_retry_token,
             identifier: "MT-561",
             error: "agent exited: :boom"
           } = :sys.get_state(pid).retry_attempts[issue_id]

    assert log =~ "issue_retry_cancelled"
    assert log =~ "reason=stale_retry_token"
  end

  test "retry timer emits started event before processing retry lookup" do
    issue_id = "issue-retry-started"
    retry_token = make_ref()
    orchestrator_name = __MODULE__.RetryStartedOrchestrator

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      tracker_active_states: ["Todo", "In Progress"],
      tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
    )

    Application.put_env(:symphony_elixir, :memory_tracker_issues, [])

    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name, schedule_initial_poll?: false)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :memory_tracker_issues)

      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:retry_attempts, %{
        issue_id => %{
          attempt: 2,
          timer_ref: nil,
          retry_token: retry_token,
          due_at_ms: System.monotonic_time(:millisecond) + 30_000,
          identifier: "MT-562",
          error: "agent exited: :boom"
        }
      })
      |> Map.put(:claimed, MapSet.new([issue_id]))
    end)

    log =
      capture_log(fn ->
        send(pid, {:retry_issue, issue_id, retry_token})
        Process.sleep(50)
      end)

    state = :sys.get_state(pid)

    refute Map.has_key?(state.retry_attempts, issue_id)
    refute MapSet.member?(state.claimed, issue_id)
    assert log =~ "issue_retry_started"
    assert log =~ "attempt=2"
    assert log =~ "issue_retry_released"
  end

  test "startup terminal cleanup emits skipped event when no terminal issues exist" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-terminal-cleanup-skip-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: test_root,
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
      )

      Application.put_env(:symphony_elixir, :memory_tracker_issues, [])
      orchestrator_name = __MODULE__.TerminalCleanupSkipOrchestrator

      log =
        capture_log(fn ->
          assert {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)
          GenServer.stop(pid)
        end)

      assert log =~ "terminal_cleanup_skipped"
      assert log =~ "reason=no_terminal_issues"
    after
      Application.delete_env(:symphony_elixir, :memory_tracker_issues)
      File.rm_rf(test_root)
    end
  end

  test "startup terminal cleanup is best effort when terminal fetch raises" do
    orchestrator_name = __MODULE__.TerminalCleanupFetchRaisesOrchestrator

    log =
      capture_log(fn ->
        assert {:ok, pid} =
                 Orchestrator.start_link(
                   name: orchestrator_name,
                   terminal_cleanup_opts: [
                     fetch_terminal_issues: fn -> raise ArgumentError, "terminal fetch boom" end,
                     cleanup_workspace: fn _identifier -> :ok end,
                     emit_event: fn level, event, extra_fields ->
                       SymphonyElixir.Observability.Logger.emit(level, event, extra_fields)
                     end
                   ]
                 )

        GenServer.stop(pid)
      end)

    assert log =~ "terminal_cleanup_skipped"
    assert log =~ "startup_terminal_cleanup_failed"
    assert log =~ "terminal fetch boom"
  end

  test "startup terminal cleanup is best effort when workspace cleanup raises" do
    orchestrator_name = __MODULE__.TerminalCleanupWorkspaceCleanupRaisesOrchestrator

    log =
      capture_log(fn ->
        assert {:ok, pid} =
                 Orchestrator.start_link(
                   name: orchestrator_name,
                   terminal_cleanup_opts: [
                     fetch_terminal_issues: fn ->
                       {:ok, [%Issue{id: "issue-terminal-cleanup", identifier: "MT-TERMINAL"}]}
                     end,
                     cleanup_workspace: fn "MT-TERMINAL" -> raise ArgumentError, "cleanup boom" end,
                     emit_event: fn level, event, extra_fields ->
                       SymphonyElixir.Observability.Logger.emit(level, event, extra_fields)
                     end
                   ]
                 )

        GenServer.stop(pid)
      end)

    assert log =~ "startup_terminal_cleanup_failed"
    assert log =~ "cleanup boom"
  end

  test "startup terminal cleanup emits completed event after removing terminal workspaces" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-terminal-cleanup-complete-#{System.unique_integer([:positive])}"
      )

    workspace = Path.join(test_root, "MT-TERMINAL")

    try do
      File.mkdir_p!(workspace)

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "memory",
        workspace_root: test_root,
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
      )

      Application.put_env(:symphony_elixir, :memory_tracker_issues, [
        %Issue{
          id: "issue-terminal-cleanup",
          identifier: "MT-TERMINAL",
          state: "Closed",
          title: "Terminal cleanup",
          description: "Cleanup startup workspace",
          labels: []
        }
      ])

      orchestrator_name = __MODULE__.TerminalCleanupCompletedOrchestrator

      log =
        capture_log(fn ->
          assert {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)
          GenServer.stop(pid)
        end)

      refute File.exists?(workspace)
      assert log =~ "terminal_cleanup_completed"
      assert log =~ "cleanup_targets=1"
    after
      Application.delete_env(:symphony_elixir, :memory_tracker_issues)
      File.rm_rf(test_root)
    end
  end

  test "manual refresh coalesces repeated requests and ignores superseded ticks" do
    now_ms = System.monotonic_time(:millisecond)
    stale_tick_token = make_ref()

    state = %Orchestrator.State{
      poll_interval_ms: 30_000,
      max_concurrent_agents: 1,
      next_poll_due_at_ms: now_ms + 30_000,
      poll_check_in_progress: false,
      tick_timer_ref: nil,
      tick_token: stale_tick_token,
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      agent_rate_limits: nil
    }

    assert {:reply, %{queued: true, coalesced: false}, refreshed_state} =
             Orchestrator.handle_call(:request_refresh, {self(), make_ref()}, state)

    assert is_reference(refreshed_state.tick_timer_ref)
    assert is_reference(refreshed_state.tick_token)
    refute refreshed_state.tick_token == stale_tick_token
    assert refreshed_state.next_poll_due_at_ms <= System.monotonic_time(:millisecond)

    assert {:reply, %{queued: true, coalesced: true}, coalesced_state} =
             Orchestrator.handle_call(:request_refresh, {self(), make_ref()}, refreshed_state)

    assert coalesced_state.tick_token == refreshed_state.tick_token

    assert {:noreply, ^coalesced_state} =
             Orchestrator.handle_info({:tick, stale_tick_token}, coalesced_state)
  end

  test "select_worker_host skips full ssh hosts under the shared per-host cap" do
    write_workflow_file!(Workflow.workflow_file_path(),
      worker_ssh_hosts: ["worker-a", "worker-b"],
      worker_max_concurrent_agents_per_host: 1
    )

    state = %Orchestrator.State{
      running: %{
        "issue-1" => %{worker_host: "worker-a"}
      }
    }

    assert select_worker_host(state, nil) == "worker-b"
  end

  test "select_worker_host returns no_worker_capacity when every ssh host is full" do
    write_workflow_file!(Workflow.workflow_file_path(),
      worker_ssh_hosts: ["worker-a", "worker-b"],
      worker_max_concurrent_agents_per_host: 1
    )

    state = %Orchestrator.State{
      running: %{
        "issue-1" => %{worker_host: "worker-a"},
        "issue-2" => %{worker_host: "worker-b"}
      }
    }

    assert select_worker_host(state, nil) == :no_worker_capacity
  end

  test "select_worker_host keeps the preferred ssh host when it still has capacity" do
    write_workflow_file!(Workflow.workflow_file_path(),
      worker_ssh_hosts: ["worker-a", "worker-b"],
      worker_max_concurrent_agents_per_host: 2
    )

    state = %Orchestrator.State{
      running: %{
        "issue-1" => %{worker_host: "worker-a"},
        "issue-2" => %{worker_host: "worker-b"}
      }
    }

    assert select_worker_host(state, "worker-a") == "worker-a"
  end

  test "select_worker_host enforces the local runtime concurrency cap" do
    write_workflow_file!(Workflow.workflow_file_path(),
      worker_max_concurrent_local_agents: 1
    )

    empty_state = %Orchestrator.State{running: %{}}
    assert select_worker_host(empty_state, nil) == nil

    full_state = %Orchestrator.State{
      running: %{
        "issue-1" => %{worker_host: nil}
      }
    }

    assert select_worker_host(full_state, nil) == :no_worker_capacity
  end

  test "select_worker_host does not apply local caps to Worker Daemon placement" do
    write_workflow_file!(Workflow.workflow_file_path(),
      worker_max_concurrent_local_agents: 1,
      agent_runtime: %{
        placement: "worker_daemon",
        worker_daemon: %{endpoint: "http://daemon.example"}
      }
    )

    state = %Orchestrator.State{
      running: %{
        "issue-1" => %{worker_host: nil, worker_daemon_endpoint: "http://daemon.example"}
      }
    }

    assert select_worker_host(state, nil) == nil
  end

  defp assert_due_in_range(due_at_ms, min_remaining_ms, max_remaining_ms) do
    remaining_ms = due_at_ms - System.monotonic_time(:millisecond)

    assert remaining_ms >= min_remaining_ms
    assert remaining_ms <= max_remaining_ms
  end

  defp reconcile_issue_states(issues, state) when is_list(issues) do
    Running.reconcile_issue_states(
      issues,
      state,
      OrchestratorRuntime.dispatch_context(),
      ServerOptions.running_opts(state)
    )
  end

  defp select_worker_host(state, preferred_worker_host) do
    WorkerHosts.select_host(state, preferred_worker_host)
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)

  test "fetch issues by states with empty state set is a no-op" do
    assert {:ok, []} = Client.fetch_issues_by_states([], TrackerConfig.current!())
  end

  test "prompt builder renders issue and attempt values from workflow template" do
    workflow_prompt =
      "Ticket {{ issue.identifier }} {{ issue.title }} labels={{ issue.labels }} attempt={{ attempt }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "S-1",
      title: "Refactor backend request path",
      description: "Replace transport layer",
      state: "Todo",
      url: "https://example.org/issues/S-1",
      labels: ["backend"]
    }

    prompt = PromptBuilder.build_prompt(issue, attempt: 3)

    assert prompt =~ "Ticket S-1 Refactor backend request path"
    assert prompt =~ "labels=backend"
    assert prompt =~ "attempt=3"
  end

  test "prompt builder renders repo config values from workflow template" do
    workflow_prompt =
      "base={{ repo.base_branch }} label={% if repo.provider.options.required_pr_label %}{{ repo.provider.options.required_pr_label }}{% else %}none{% endif %}"

    write_workflow_file!(Workflow.workflow_file_path(),
      prompt: workflow_prompt,
      repo_base_branch: "master",
      repo_provider_required_pr_label: "release-ready"
    )

    issue = %Issue{
      identifier: "S-2",
      title: "Repo-backed template vars",
      description: "Render repo config",
      state: "Todo",
      url: "https://example.org/issues/S-2",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, repo: Config.settings!().repo)

    assert prompt == "base=master label=release-ready"
  end

  test "prompt builder renders per-issue workflow metadata" do
    workflow_prompt =
      "type={{ issue.workitem_type_id }} review={{ issue.workflow.raw_state_by_route_key.review }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "S-2A",
      title: "Workflow metadata",
      description: "Render per-type workflow values",
      state: "coding",
      workitem_type_id: "1153070854001000002",
      workflow: %{
        raw_state_by_route_key: %{review: "qa_review"}
      },
      url: "https://example.org/issues/S-2A",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, repo: Config.settings!().repo)

    assert prompt == "type=1153070854001000002 review=qa_review"
  end

  test "prompt builder renders per-issue route policy metadata" do
    workflow_prompt =
      "planning={{ issue.workflow.policy_by_route_key.planning.action }} " <>
        "target={{ issue.workflow.policy_by_route_key.planning.transition_target }} " <>
        "merging={{ issue.workflow.policy_by_route_key.merging.execution_profile }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "S-2B",
      title: "Route policy metadata",
      description: "Render per-issue route policies",
      state: "status_4",
      workflow: %{
        policy_by_route_key: %{
          planning: %{action: :transition_then_dispatch, transition_target: :developing},
          merging: %{action: :dispatch, execution_profile: "land"}
        }
      },
      url: "https://example.org/issues/S-2B",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, repo: Config.settings!().repo)

    assert prompt == "planning=transition_then_dispatch target=developing merging=land"
  end

  test "prompt builder renders structured workflow readiness context" do
    workflow_prompt =
      "profile={{ workflow.profile.kind }} " <>
        "route={{ workflow.route.key }} " <>
        "action={{ workflow.route.action }} " <>
        "gate={{ workflow.gate.status }}/{{ workflow.gate.gate }} " <>
        "routes={{ workflow.completion_contract.allowed_completion_routes }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "S-2C",
      title: "Workflow readiness metadata",
      description: "Render structured workflow facts",
      state: "In Review",
      lifecycle_phase: "human_review",
      workflow: %{
        profile: %{
          "kind" => "coding_pr_delivery",
          "version" => 1,
          "options" => %{"requirements" => %{"change_proposal" => true}}
        },
        raw_state_by_route_key: %{
          planning: "Todo",
          developing: "In Progress",
          review: "In Review",
          merging: "Merging",
          rework: "Rework",
          resolved: "Done",
          rejected: "Closed"
        },
        policy_by_route_key: %{
          planning: %{action: :transition_then_dispatch, transition_target: :developing},
          developing: %{action: :dispatch},
          review: %{action: :wait},
          merging: %{action: :dispatch, execution_profile: "land"},
          rework: %{action: :dispatch},
          resolved: %{action: :stop},
          rejected: %{action: :stop}
        }
      },
      url: "https://example.org/issues/S-2C",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, repo: Config.settings!().repo)

    assert prompt =~ "profile=coding_pr_delivery"
    assert prompt =~ "route=review"
    assert prompt =~ "action=wait"
    assert prompt =~ "gate=waiting/approval"
    assert prompt =~ "review"
    assert prompt =~ "merging"
  end

  test "prompt builder resolves workflow route from settings lifecycle when issue omits workflow metadata" do
    workflow_prompt =
      "route={{ workflow.route.key }} action={{ workflow.route.action }} gate={{ workflow.gate.status }}/{{ workflow.gate.gate }}"

    write_workflow_file!(Workflow.workflow_file_path(),
      prompt: workflow_prompt,
      tracker_active_states: ["Todo", "In Progress", "Merging", "Rework"],
      tracker_terminal_states: ["Done", "Closed", "Cancelled", "Canceled", "Duplicate"]
    )

    settings = Config.settings!()

    issue = %Issue{
      identifier: "S-2D",
      title: "Settings-backed route facts",
      description: "Render Linear route facts",
      state: "In Progress",
      lifecycle_phase: "in_progress",
      url: "https://example.org/issues/S-2D",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, settings: settings, repo: settings.repo)

    assert prompt == "route=developing action=dispatch gate=open/dispatch"
  end

  test "prompt builder keeps workflow facts renderable when route is unresolved" do
    workflow_prompt =
      "route={% if workflow.route.key %}{{ workflow.route.key }}{% else %}unresolved{% endif %} " <>
        "gate={{ workflow.gate.status }}/{{ workflow.gate.gate }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "S-2E",
      title: "Unresolved route facts",
      description: "Render empty route facts",
      state: "External State",
      url: "https://example.org/issues/S-2E",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, repo: Config.settings!().repo)

    assert prompt == "route=unresolved gate=blocked/route"
  end

  test "prompt builder handles missing repo label via conditional template" do
    workflow_prompt =
      "base={{ repo.base_branch }} label={% if repo.provider.options.required_pr_label %}{{ repo.provider.options.required_pr_label }}{% else %}none{% endif %}"

    write_workflow_file!(Workflow.workflow_file_path(),
      prompt: workflow_prompt,
      repo_base_branch: "main",
      repo_provider_required_pr_label: nil
    )

    issue = %Issue{
      identifier: "S-3",
      title: "Optional repo label",
      description: "Conditional repo label",
      state: "Todo",
      url: "https://example.org/issues/S-3",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, repo: Config.settings!().repo)

    assert prompt == "base=main label=none"
  end

  test "prompt builder can scope repo label workflow text to GitHub only" do
    workflow_prompt =
      "{% if repo.provider.kind == \"github\" %}{% if repo.provider.options.required_pr_label %}label={{ repo.provider.options.required_pr_label }}{% else %}label=none{% endif %}{% else %}provider={{ repo.provider.kind }}{% endif %}"

    write_workflow_file!(Workflow.workflow_file_path(),
      prompt: workflow_prompt,
      repo_provider_kind: "cnb",
      repo_provider_required_pr_label: "release-ready"
    )

    issue = %Issue{
      identifier: "S-3A",
      title: "Provider-scoped repo label",
      description: "Conditional provider-specific label text",
      state: "Todo",
      url: "https://example.org/issues/S-3A",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, repo: Config.settings!().repo)

    assert prompt == "provider=cnb"
  end

  test "prompt builder renders issue datetime fields without crashing" do
    workflow_prompt =
      "Ticket {{ issue.identifier }} created={{ issue.created_at }} updated={{ issue.updated_at }}"

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    created_at = DateTime.from_naive!(~N[2026-02-26 18:06:48], "Etc/UTC")
    updated_at = DateTime.from_naive!(~N[2026-02-26 18:07:03], "Etc/UTC")

    issue = %Issue{
      identifier: "MT-697",
      title: "Live smoke",
      description: "Prompt should serialize datetimes",
      state: "Todo",
      url: "https://example.org/issues/MT-697",
      labels: [],
      created_at: created_at,
      updated_at: updated_at
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "Ticket MT-697"
    assert prompt =~ "created=2026-02-26T18:06:48Z"
    assert prompt =~ "updated=2026-02-26T18:07:03Z"
  end

  test "prompt builder normalizes nested date-like values, maps, and structs in issue fields" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "Ticket {{ issue.identifier }}")

    issue = %Issue{
      identifier: "MT-701",
      title: "Serialize nested values",
      description: "Prompt builder should normalize nested terms",
      state: "Todo",
      url: "https://example.org/issues/MT-701",
      labels: [
        ~N[2026-02-27 12:34:56],
        ~D[2026-02-28],
        ~T[12:34:56],
        %{phase: "test"},
        URI.parse("https://example.org/issues/MT-701")
      ]
    }

    assert PromptBuilder.build_prompt(issue) == "Ticket MT-701"
  end

  test "prompt builder uses strict variable rendering" do
    workflow_prompt = "Work on ticket {{ missing.ticket_id }} and follow these steps."

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "MT-123",
      title: "Investigate broken sync",
      description: "Reproduce and fix",
      state: "In Progress",
      url: "https://example.org/issues/MT-123",
      labels: ["bug"]
    }

    log =
      capture_log(fn ->
        assert_raise Solid.RenderError, fn ->
          PromptBuilder.build_prompt(issue)
        end
      end)

    assert log =~ "prompt_render_failed"
    assert log =~ "issue_identifier=MT-123"
  end

  test "prompt builder surfaces invalid template content with prompt context" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "{% if issue.identifier %}")

    issue = %Issue{
      identifier: "MT-999",
      title: "Broken prompt",
      description: "Invalid template syntax",
      state: "Todo",
      url: "https://example.org/issues/MT-999",
      labels: []
    }

    log =
      capture_log(fn ->
        assert_raise RuntimeError, ~r/template_parse_error:.*template="/s, fn ->
          PromptBuilder.build_prompt(issue)
        end
      end)

    assert log =~ "prompt_template_parse_failed"
    assert log =~ "issue_identifier=MT-999"
  end

  test "prompt builder uses a sensible default template when workflow prompt is blank" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "   \n")

    issue = %Issue{
      identifier: "MT-777",
      title: "Make default prompt useful",
      description: "Include enough issue context to start working.",
      state: "In Progress",
      url: "https://example.org/issues/MT-777",
      labels: ["prompt"]
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "You are working on an issue."
    assert prompt =~ "Identifier: MT-777"
    assert prompt =~ "Title: Make default prompt useful"
    assert prompt =~ "Body:"
    assert prompt =~ "Include enough issue context to start working."
    assert Config.workflow_prompt() =~ "{{ issue.identifier }}"
    assert Config.workflow_prompt() =~ "{{ issue.title }}"
    assert Config.workflow_prompt() =~ "{{ issue.description }}"
  end

  test "prompt builder default template handles missing issue body" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "")

    issue = %Issue{
      identifier: "MT-778",
      title: "Handle empty body",
      description: nil,
      state: "Todo",
      url: "https://example.org/issues/MT-778",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "Identifier: MT-778"
    assert prompt =~ "Title: Handle empty body"
    assert prompt =~ "No description provided."
  end

  test "prompt builder reports workflow load failures separately from template parse errors" do
    original_workflow_path = Workflow.workflow_file_path()
    workflow_store_pid = Process.whereis(SymphonyElixir.Workflow.Runtime.Store)

    on_exit(fn ->
      Workflow.set_workflow_file_path(original_workflow_path)

      if is_pid(workflow_store_pid) and
           is_nil(Process.whereis(SymphonyElixir.Workflow.Runtime.Store)) do
        assert :ok = restart_supervised_child(SymphonyElixir.Workflow.Runtime.Store)
      end
    end)

    assert :ok = terminate_supervised_child(SymphonyElixir.Workflow.Runtime.Store)

    Workflow.set_workflow_file_path(Path.join(System.tmp_dir!(), "missing-workflow-#{System.unique_integer([:positive])}.md"))

    issue = %Issue{
      identifier: "MT-780",
      title: "Workflow unavailable",
      description: "Missing workflow file",
      state: "Todo",
      url: "https://example.org/issues/MT-780",
      labels: []
    }

    log =
      capture_log(fn ->
        assert_raise RuntimeError, ~r/workflow_unavailable:/, fn ->
          PromptBuilder.build_prompt(issue)
        end
      end)

    assert log =~ "prompt_workflow_unavailable"
    assert log =~ "issue_identifier=MT-780"
  end

  test "in-repo WORKFLOW.md renders correctly" do
    workflow_path = Workflow.workflow_file_path()
    Workflow.set_workflow_file_path(Path.expand("WORKFLOW.md", File.cwd!()))

    issue = %Issue{
      identifier: "MT-616",
      title: "Use rich templates for WORKFLOW.md",
      description: "Render with rich template variables",
      state: "In Progress",
      url: "https://example.org/issues/MT-616/use-rich-templademo-for-workflowmd",
      labels: ["templating", "workflow"]
    }

    on_exit(fn -> Workflow.set_workflow_file_path(workflow_path) end)

    settings = Config.settings!()
    prompt = PromptBuilder.build_prompt(issue, attempt: 2, settings: settings, repo: settings.repo)

    assert prompt =~ "You are working on a Linear ticket `MT-616`"
    assert prompt =~ "Issue context:"
    assert prompt =~ "Identifier: MT-616"
    assert prompt =~ "Title: Use rich templates for WORKFLOW.md"
    assert prompt =~ "Current status: In Progress"
    assert prompt =~ "https://example.org/issues/MT-616/use-rich-templademo-for-workflowmd"
    assert prompt =~ "Workflow facts:"
    assert prompt =~ "profile -> `coding_pr_delivery` v1"
    assert prompt =~ "current route -> `developing`; action -> `dispatch`; gate -> `open/dispatch`"
    assert prompt =~ "completion routes ->"
    assert prompt =~ "This is an unattended orchestration session."
    assert prompt =~ "Only stop early for a true blocker"
    assert prompt =~ "Do not include \"next steps for user\""
    assert prompt =~ "The active repo provider for bundled automation is `github`."
    assert prompt =~ "When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` exists"

    assert prompt =~
             "When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` exists"

    assert prompt =~
             "open workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists"

    assert prompt =~
             "Otherwise, use the inventory `repo.merge_change_proposal` typed tool when it is listed"

    assert prompt =~ "origin/#{Config.settings!().repo.base_branch}"
    refute prompt =~ "Required PR metadata is present (` label)."
    assert prompt =~ "Continuation context:"
    assert prompt =~ "retry attempt #2"
  end

  test "bundled TAPD GitHub Codex workflow template renders per-issue workflow contract" do
    workflow_path = Workflow.workflow_file_path()
    Workflow.set_workflow_file_path(tapd_github_codex_workflow_template_path())

    issue = %Issue{
      id: "42",
      identifier: "TAPD-42",
      title: "Render TAPD workflow routes",
      description: "Verify per-type route placeholders resolve from issue workflow metadata",
      state: "queued",
      workitem_type_id: "feature",
      workflow: %{
        raw_state_by_route_key: %{
          planning: "queued",
          developing: "coding",
          review: "qa_review",
          merging: "shipping",
          rework: "fixback",
          resolved: "done",
          rejected: "canceled"
        },
        policy_by_route_key: %{
          planning: %{action: :transition_then_dispatch, transition_target: :developing},
          developing: %{action: :dispatch},
          review: %{action: :wait},
          merging: %{action: :dispatch, execution_profile: "land"},
          rework: %{action: :dispatch},
          resolved: %{action: :stop},
          rejected: %{action: :stop}
        },
        completion_contract: %{
          required_outputs: ["Validation evidence recorded."],
          allowed_completion_routes: ["review", "merging", "rework", "resolved", "rejected"],
          evidence_requirements: ["Test, check, or manual validation evidence when available."],
          handoff_expectations: ["Tracker comment or status surface records the result."]
        }
      },
      url: "https://example.org/tapd/stories/view/42",
      labels: ["tapd", "workflow"]
    }

    on_exit(fn -> Workflow.set_workflow_file_path(workflow_path) end)

    prompt = PromptBuilder.build_prompt(issue, attempt: 2, repo: Config.settings!().repo)

    assert prompt =~ "You are working on a TAPD story `TAPD-42`"
    assert prompt =~ "Workitem type: feature"
    assert prompt =~ "Current workflow contract for this Story:"

    assert prompt =~
             "planning: raw state `queued`; policy `transition_then_dispatch` -> `developing`"

    assert prompt =~ "review: raw state `qa_review`; policy `wait`"

    assert prompt =~
             "`planning` route -> raw state `queued`; policy `transition_then_dispatch` to route `developing`."

    assert prompt =~ "Symphony normally performs that transition before the agent session starts"

    assert prompt =~
             "`merging` route -> raw state `shipping`; policy `dispatch` with execution profile `land`."

    assert prompt =~ "Completion contract:"
    assert prompt =~ "allowed completion routes ->"
    assert prompt =~ "Validation evidence recorded."
    assert prompt =~ "## Route-Policy Precedence"
    assert prompt =~ "the resolved route-policy facts win"
    assert prompt =~ "Never treat this prompt as authority to perform backend-owned pre-dispatch"

    assert prompt =~
             "do not rely on prompt text to decide or perform the pre-dispatch transition yourself"

    assert prompt =~
             "Use this protocol before moving a story into its next non-dispatch handoff route."

    assert prompt =~ "Do not move a story into a non-dispatch handoff route such as `qa_review`"
    assert prompt =~ "## Completion Bar Before Non-Dispatch Handoff"
    assert prompt =~ "retry attempt #2"
  end

  test "prompt builder adds continuation guidance for retries" do
    workflow_prompt = "{% if attempt %}Retry #" <> "{{ attempt }}" <> "{% endif %}"
    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)

    issue = %Issue{
      identifier: "MT-201",
      title: "Continue autonomous ticket",
      description: "Retry flow",
      state: "In Progress",
      url: "https://example.org/issues/MT-201",
      labels: []
    }

    prompt = PromptBuilder.build_prompt(issue, attempt: 2)

    assert prompt == "Retry #2"
  end

  test "agent runner keeps workspace after successful codex run" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-retain-workspace-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(template_repo)
      File.mkdir_p!(workspace_root)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])

      CommandEnv.system_cmd("git", [
        "-C",
        template_repo,
        "config",
        "user.email",
        "test@example.com"
      ])

      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        case "$count" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-1\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-1\"}}}'
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        identifier: "S-99",
        title: "Smoke test",
        description: "Run and keep workspace",
        state: "In Progress",
        url: "https://example.org/issues/S-99",
        labels: ["backend"]
      }

      before = MapSet.new(File.ls!(workspace_root))
      assert :ok = AgentRunner.run(issue, nil, http_port: 4521)
      entries_after = MapSet.new(File.ls!(workspace_root))

      created =
        MapSet.difference(entries_after, before) |> Enum.filter(&(&1 == "S-99"))

      created = MapSet.new(created)

      assert MapSet.size(created) == 1
      workspace_name = created |> Enum.to_list() |> List.first()
      assert workspace_name == "S-99"

      workspace = Path.join(workspace_root, workspace_name)
      assert File.exists?(workspace)
      assert File.exists?(Path.join(workspace, "README.md"))
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner forwards timestamped codex updates to recipient" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-updademo-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])

      CommandEnv.system_cmd("git", [
        "-C",
        template_repo,
        "config",
        "user.email",
        "test@example.com"
      ])

      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(
        codex_binary,
        """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          case "$count" in
            1)
              printf '%s\\n' '{\"id\":1,\"result\":{}}'
              ;;
            2)
              printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-live\"}}}'
              ;;
            3)
              printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-live\"}}}'
              ;;
            4)
              printf '%s\\n' '{\"method\":\"turn/completed\"}'
              ;;
            *)
              ;;
          esac
        done
        """
      )

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-live-updates",
        identifier: "MT-99",
        title: "Smoke test",
        description: "Capture codex updates",
        state: "In Progress",
        url: "https://example.org/issues/MT-99",
        labels: ["backend"]
      }

      test_pid = self()

      assert :ok =
               AgentRunner.run(
                 issue,
                 test_pid,
                 http_port: 4521,
                 issue_state_fetcher: fn [_issue_id] -> {:ok, [%{issue | state: "Done"}]} end
               )

      assert_receive {:agent_worker_update, "issue-live-updates",
                      %{
                        event: :session_started,
                        timestamp: %DateTime{},
                        session_id: session_id
                      }},
                     500

      assert session_id == "thread-live-turn-live"
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner surfaces ssh startup failures instead of silently hopping hosts" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-single-host-#{System.unique_integer([:positive])}"
      )

    previous_path = System.get_env("PATH")
    previous_trace = System.get_env("SYMP_TEST_SSH_TRACE")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMP_TEST_SSH_TRACE", previous_trace)
    end)

    try do
      trace_file = Path.join(test_root, "ssh.trace")
      fake_ssh = Path.join(test_root, "ssh")

      File.mkdir_p!(test_root)
      System.put_env("SYMP_TEST_SSH_TRACE", trace_file)
      System.put_env("PATH", test_root <> ":" <> (previous_path || ""))

      File.write!(fake_ssh, """
      #!/bin/sh
      trace_file="${SYMP_TEST_SSH_TRACE:-/tmp/symphony-fake-ssh.trace}"
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"

      case "$*" in
        *worker-a*"__SYMPHONY_WORKSPACE__"*)
          printf '%s\\n' 'worker-a prepare failed' >&2
          exit 75
          ;;
        *worker-b*"__SYMPHONY_WORKSPACE__"*)
          printf '%s\\t%s\\t%s\\n' '__SYMPHONY_WORKSPACE__' '1' '/remote/home/.symphony-remote-workspaces/MT-SSH-FAILOVER'
          exit 0
          ;;
        *)
          exit 0
          ;;
      esac
      """)

      File.chmod!(fake_ssh, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: "~/.symphony-remote-workspaces",
        worker_ssh_hosts: ["worker-a", "worker-b"]
      )

      issue = %Issue{
        id: "issue-ssh-failover",
        identifier: "MT-SSH-FAILOVER",
        title: "Do not fail over within a single worker run",
        description: "Surface the startup failure to the orchestrator",
        state: "In Progress"
      }

      log =
        capture_log(fn ->
          assert_raise RuntimeError, ~r/workspace_prepare_failed/, fn ->
            AgentRunner.run(issue, nil, worker_host: "worker-a")
          end
        end)

      trace = File.read!(trace_file)
      assert trace =~ "worker-a bash -lc"
      refute trace =~ "worker-b bash -lc"
      assert log =~ "failure_class=workspace_prepare_failure"
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner closes codex sessions as failed when a turn errors" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-turn-failure-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])

      CommandEnv.system_cmd("git", [
        "-C",
        template_repo,
        "config",
        "user.email",
        "test@example.com"
      ])

      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        case "$count" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-fail\"}}}'
            ;;
          3)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-fail\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"method\":\"error\",\"params\":{\"message\":\"rate limit exhausted\",\"code\":\"rate_limited\"}}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-turn-failure",
        identifier: "MT-249",
        title: "Surface codex turn failures",
        description: "Ensure session close logging is terminal and unambiguous",
        state: "In Progress",
        url: "https://example.org/issues/MT-249",
        labels: ["backend"]
      }

      log =
        capture_log(fn ->
          assert_raise RuntimeError, fn ->
            AgentRunner.run(issue, nil, http_port: 4521)
          end
        end)

      assert log =~ "codex_turn_failed"
      assert log =~ "codex_session_failed"
      refute log =~ "codex_session_completed"
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner continues with a follow-up turn while the issue remains active" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-continuation-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex.trace")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])

      CommandEnv.system_cmd("git", [
        "-C",
        template_repo,
        "config",
        "user.email",
        "test@example.com"
      ])

      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex.trace}"
      run_id="$(date +%s%N)-$$"
      printf 'RUN:%s\\n' "$run_id" >> "$trace_file"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-cont"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-cont-1"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
          5)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-cont-2"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)
      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)

      on_exit(fn -> System.delete_env("SYMP_TEST_CODEx_TRACE") end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        agent_provider_options: %{command: "#{codex_binary} app-server"},
        max_turns: 3
      )

      parent = self()

      state_fetcher = fn [_issue_id] ->
        attempt = Process.get(:agent_turn_fetch_count, 0) + 1
        Process.put(:agent_turn_fetch_count, attempt)
        send(parent, {:issue_state_fetch, attempt})

        state =
          if attempt == 1 do
            "In Progress"
          else
            "Done"
          end

        {:ok,
         [
           %Issue{
             id: "issue-continue",
             identifier: "MT-247",
             title: "Continue until done",
             description: "Still active after first turn",
             state: state
           }
         ]}
      end

      issue = %Issue{
        id: "issue-continue",
        identifier: "MT-247",
        title: "Continue until done",
        description: "Still active after first turn",
        state: "In Progress",
        url: "https://example.org/issues/MT-247",
        labels: []
      }

      assert :ok = AgentRunner.run(issue, nil, http_port: 4521, issue_state_fetcher: state_fetcher)
      assert_receive {:issue_state_fetch, 1}
      assert_receive {:issue_state_fetch, 2}

      lines = File.read!(trace_file) |> String.split("\n", trim: true)

      assert length(Enum.filter(lines, &String.starts_with?(&1, "RUN:"))) == 1
      assert length(Enum.filter(lines, &String.contains?(&1, "\"method\":\"thread/start\""))) == 1

      turn_texts =
        lines
        |> Enum.filter(&String.starts_with?(&1, "JSON:"))
        |> Enum.map(&String.trim_leading(&1, "JSON:"))
        |> Enum.map(&Jason.decode!/1)
        |> Enum.filter(&(&1["method"] == "turn/start"))
        |> Enum.map(fn payload ->
          get_in(payload, ["params", "input"])
          |> Enum.map_join("\n", &Map.get(&1, "text", ""))
        end)

      assert length(turn_texts) == 2
      assert Enum.at(turn_texts, 0) =~ "You are an agent for this repository."
      refute Enum.at(turn_texts, 1) =~ "You are an agent for this repository."
      assert Enum.at(turn_texts, 1) =~ "Continuation guidance:"
      assert Enum.at(turn_texts, 1) =~ "continuation turn #2 of 3"
    after
      System.delete_env("SYMP_TEST_CODEx_TRACE")
      File.rm_rf(test_root)
    end
  end

  test "agent runner stops continuing once agent.execution.max_turns is reached" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-max-turns-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex.trace")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "# test")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])

      CommandEnv.system_cmd("git", [
        "-C",
        template_repo,
        "config",
        "user.email",
        "test@example.com"
      ])

      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex.trace}"
      printf 'RUN\\n' >> "$trace_file"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-max"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-max-1"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
          5)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-max-2"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)
      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)

      on_exit(fn -> System.delete_env("SYMP_TEST_CODEx_TRACE") end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
        agent_provider_options: %{command: "#{codex_binary} app-server"},
        max_turns: 2
      )

      state_fetcher = fn [_issue_id] ->
        {:ok,
         [
           %Issue{
             id: "issue-max-turns",
             identifier: "MT-248",
             title: "Stop at max turns",
             description: "Still active",
             state: "In Progress"
           }
         ]}
      end

      issue = %Issue{
        id: "issue-max-turns",
        identifier: "MT-248",
        title: "Stop at max turns",
        description: "Still active",
        state: "In Progress",
        url: "https://example.org/issues/MT-248",
        labels: []
      }

      assert :ok = AgentRunner.run(issue, nil, http_port: 4521, issue_state_fetcher: state_fetcher)

      trace = File.read!(trace_file)
      assert length(String.split(trace, "RUN", trim: true)) == 1
      assert length(Regex.scan(~r/"method":"turn\/start"/, trace)) == 2
    after
      System.delete_env("SYMP_TEST_CODEx_TRACE")
      File.rm_rf(test_root)
    end
  end

  test "app server starts with workspace cwd and expected startup command" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-args-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-77")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-args.trace")
      previous_trace = System.get_env("SYMP_TEST_CODex_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODex_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODex_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODex_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODex_TRACE:-/tmp/codex-args.trace}"
      count=0
      printf 'ARGV:%s\\n' \"$*\" >> \"$trace_file\"
      printf 'CWD:%s\\n' \"$PWD\" >> \"$trace_file\"
      printf 'ENV:KIND=%s\\n' "${SYMPHONY_REPO_PROVIDER_KIND:-}" >> "$trace_file"
      printf 'ENV:REPOSITORY=%s\\n' "${SYMPHONY_REPO_PROVIDER_REPOSITORY:-}" >> "$trace_file"
      printf 'ENV:API_BASE=%s\\n' "${SYMPHONY_REPO_PROVIDER_API_BASE_URL:-}" >> "$trace_file"
      printf 'ENV:WEB_BASE=%s\\n' "${SYMPHONY_REPO_PROVIDER_WEB_BASE_URL:-}" >> "$trace_file"

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"
        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-77\"}}}'
            ;;
          3)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-77\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"},
        repo_provider_repository: "acme/widgets",
        repo_provider_api_base_url: "https://api.github.example.test",
        repo_provider_web_base_url: "https://github.example.test"
      )

      issue = %Issue{
        id: "issue-args",
        identifier: "MT-77",
        title: "Validate codex args",
        description: "Check startup args and cwd",
        state: "In Progress",
        url: "https://example.org/issues/MT-77",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Fix workspace start args",
                 issue,
                 codex_app_server_opts(workspace)
               )

      assert {:ok, canonical_workspace} = SymphonyElixir.PathSafety.canonicalize(workspace)

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert argv_line = Enum.find(lines, fn line -> String.starts_with?(line, "ARGV:") end)
      assert String.contains?(argv_line, "app-server")
      refute Enum.any?(lines, &String.contains?(&1, "--yolo"))
      assert cwd_line = Enum.find(lines, fn line -> String.starts_with?(line, "CWD:") end)
      assert String.ends_with?(cwd_line, Path.basename(workspace))
      assert "ENV:KIND=github" in lines
      assert "ENV:REPOSITORY=acme/widgets" in lines
      assert "ENV:API_BASE=https://api.github.example.test" in lines
      assert "ENV:WEB_BASE=https://github.example.test" in lines

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "thread/start" &&
                     get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                     get_in(payload, ["params", "sandbox"]) == "workspace-write" &&
                     get_in(payload, ["params", "cwd"]) == canonical_workspace
                 end)
               else
                 false
               end
             end)

      expected_turn_sandbox_policy = %{
        "type" => "workspaceWrite",
        "writableRoots" => [canonical_workspace],
        "readOnlyAccess" => %{"type" => "fullAccess"},
        "networkAccess" => false,
        "excludeTmpdirEnvVar" => false,
        "excludeSlashTmp" => false
      }

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "turn/start" &&
                     get_in(payload, ["params", "cwd"]) == canonical_workspace &&
                     get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                     get_in(payload, ["params", "sandboxPolicy"]) == expected_turn_sandbox_policy
                 end)
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server startup command supports codex args override from workflow config" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-custom-args-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-88")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-custom-args.trace")
      previous_trace = System.get_env("SYMP_TEST_CODex_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODex_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODex_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODex_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODex_TRACE:-/tmp/codex-custom-args.trace}"
      count=0
      printf 'ARGV:%s\\n' \"$*\" >> \"$trace_file\"

      while IFS= read -r line; do
        count=$((count + 1))
        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-88\"}}}'
            ;;
          3)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-88\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} --model gpt-5.3-codex app-server"}
      )

      issue = %Issue{
        id: "issue-custom-args",
        identifier: "MT-88",
        title: "Validate custom codex args",
        description: "Check startup args override",
        state: "In Progress",
        url: "https://example.org/issues/MT-88",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Fix workspace start args",
                 issue,
                 codex_app_server_opts(workspace)
               )

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert argv_line = Enum.find(lines, fn line -> String.starts_with?(line, "ARGV:") end)
      assert String.contains?(argv_line, "--model gpt-5.3-codex app-server")
      refute String.contains?(argv_line, "--ask-for-approval never")
      refute String.contains?(argv_line, "--sandbox danger-full-access")
    after
      File.rm_rf(test_root)
    end
  end

  test "app server startup payload uses configurable approval and sandbox settings from workflow config" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-policy-overrides-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-99")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-policy-overrides.trace")
      previous_trace = System.get_env("SYMP_TEST_CODex_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODex_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODex_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODex_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODex_TRACE:-/tmp/codex-policy-overrides.trace}"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-99"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-99"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      workspace_cache = Path.join(Path.expand(workspace), ".cache")
      File.mkdir_p!(workspace_cache)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{
          command: "#{codex_binary} app-server",
          approval_policy: "on-request",
          thread_sandbox: "workspace-write",
          turn_sandbox_policy: %{
            type: "workspaceWrite",
            writableRoots: [Path.expand(workspace), workspace_cache]
          }
        }
      )

      issue = %Issue{
        id: "issue-policy-overrides",
        identifier: "MT-99",
        title: "Validate codex policy overrides",
        description: "Check startup policy payload overrides",
        state: "In Progress",
        url: "https://example.org/issues/MT-99",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Fix workspace start args",
                 issue,
                 codex_app_server_opts(workspace)
               )

      lines = File.read!(trace_file) |> String.split("\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "thread/start" &&
                     get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                     get_in(payload, ["params", "sandbox"]) == "workspace-write"
                 end)
               else
                 false
               end
             end)

      expected_turn_policy = %{
        "type" => "workspaceWrite",
        "writableRoots" => [Path.expand(workspace), workspace_cache]
      }

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "turn/start" &&
                     get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                     get_in(payload, ["params", "sandboxPolicy"]) == expected_turn_policy
                 end)
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end
end
