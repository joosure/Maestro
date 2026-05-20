defmodule SymphonyElixir.WorkflowTemplatesTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Capabilities, as: WorkflowCapabilities
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Templates

  @forbidden_runtime_references [
    {Regex.compile!("(^|[^[:alnum:]_])(?:\\.\\./)?" <> ("spe" <> "cs") <> "/"), "repository-local private asset path"},
    {~r/\b[A-Za-z0-9_]+_spec\.md\b/, "spec markdown file"},
    {Regex.compile!("\\b" <> ("SP" <> "EC.md") <> "\\b"), "top-level private asset entrypoint"},
    {Regex.compile!("\\bintegration " <> "spec\\b", "i"), "runtime reference to private integration notes"},
    {~r|/Users/[^[:space:]"'`]+|, "local macOS user path"}
  ]

  test "bundled workflow templates are self-contained runtime guidance" do
    violations =
      Templates.paths()
      |> Enum.flat_map(&runtime_reference_violations/1)

    assert violations == []
  end

  test "bundled workflow template provider commands use portable executable names" do
    violations =
      Templates.paths()
      |> Enum.flat_map(&provider_command_violations/1)

    assert violations == []
  end

  test "template aliases resolve with and without .md, including variants" do
    {:ok, canary_path} = Templates.resolve("linear/github/opencode.canary")
    {:ok, canary_md_path} = Templates.resolve("linear/github/opencode.canary.md")

    assert canary_path == canary_md_path
    assert Path.basename(canary_path) == "opencode.canary.md"

    for template_alias <- Templates.aliases() do
      assert {:ok, _path} = Templates.resolve(template_alias)
    end
  end

  test "OpenCode canary template uses the ZAI model without managed credential lease" do
    {:ok, canary_path} = Templates.resolve("linear/github/opencode.canary")
    assert {:ok, %{config: config}} = Workflow.load(canary_path)

    options = get_in(config, ["agent_provider", "options"])

    assert options["model"] == "zai-coding-plan/glm-5.1"
    refute Map.has_key?(options, "credential_ref")
  end

  test "memory mock template provides a no-credential local workflow" do
    {:ok, template_path} = Templates.resolve("memory/no_repo/mock")
    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load(template_path)
    assert {:ok, settings} = SymphonyElixir.Config.Schema.parse(config)

    assert settings.workflow.profile["kind"] == "triage"
    assert settings.tracker.kind == "memory"
    assert settings.repo.provider.kind == "memory"
    assert settings.agent_provider.kind == "mock"
    assert settings.agent_provider.options["complete_issue_state"] == "routed"

    assert :ok = SymphonyElixir.Tracker.validate_config(settings.tracker)
    assert :ok = SymphonyElixir.RepoProvider.validate_config(settings.repo)
    assert :ok = SymphonyElixir.AgentProvider.validate_config(settings.agent_provider)

    available_capabilities = SymphonyElixir.Config.Capabilities.available_capabilities(settings)
    assert :ok = WorkflowCapabilities.validate_required_capabilities(settings, available_capabilities)

    assert {:ok, [issue]} = SymphonyElixir.Tracker.fetch_candidate_issues(settings.tracker)
    assert issue.identifier == "MEM-1"
    assert issue.state == "classifying"

    assert prompt =~ "No external tracker"
    assert prompt =~ "mock agent provider"
  end

  test "OpenCode canary template prevents incomplete repo work from entering review" do
    {:ok, canary_path} = Templates.resolve("linear/github/opencode.canary")
    template = File.read!(canary_path)

    assert template =~ "`repo/` is a workspace-relative path, not an absolute filesystem path"
    assert template =~ "Never\n  read from or write to `/repo`"
    assert template =~ "A failed read/write under `/repo/...` is a path-selection error"
    assert template =~ "Retry with workspace-relative `repo/...`"

    assert template =~
             "Missing commits, no diff, or a PR-create failure caused by no branch changes\n  is incomplete execution"

    assert template =~ "Completion bar before In Review"

    assert template =~
             "Do not move to `In Review` unless the `Completion bar before In Review` is satisfied"

    assert template =~ "PR checks are green, branch is pushed, and PR is linked on the issue"
  end

  test "Linear GitHub templates route state changes through typed tracker tools" do
    for path <- linear_github_template_paths() do
      template = File.read!(path)

      assert template =~
               "Use the inventory `tracker.move_issue` typed tool to move the issue to `In Progress`"

      assert template =~ "Linear Access Boundary"
      assert template =~ "Only use inventory-listed typed Linear tools"
      assert template =~ "do not use any non-inventory Linear access path"
      assert template =~ "Fetch the issue by explicit ticket ID through the inventory `tracker.issue_snapshot` typed tool"
      assert template =~ "Use the inventory `tracker.issue_snapshot` typed tool with comments included"
      assert template =~ "through the inventory `tracker.upsert_workpad` typed tool"
      assert template =~ "Record a short note in the workpad if state and issue content are inconsistent"
      refute template =~ "direct Linear API"
      refute template =~ "token-bearing shell"
      assert template =~ "This workflow defines when tracker actions are allowed"
      assert template =~ "If a required feedback capability is missing from the inventory"
      assert template =~ "unresolvedFeedbackSummary.unresolvedItems"
      assert template =~ "nextResponseActions"
      assert template =~ "tracker.upsert_workpad"
      assert template =~ "tracker.attach_change_proposal"
      assert template =~ "If it is missing, stop as blocked and record the missing typed tracker capability"
      assert template =~ "target repository's documented launch or runtime validation"
      assert template =~ "fallback PR link storage is recorded in the workpad"
      assert template =~ "`repo.commit` mode is `all` or `staged`"
      assert template =~ "`repo.checkout` mode is `create_or_switch`, `create`, or `switch`"
      assert template =~ "repo.change_proposal_snapshot"
      assert template =~ "Create or update the PR through the inventory `repo.create_or_update_change_proposal` typed tool"
      assert template =~ "For a new PR, pass `mode: \"create\"`, `title`, `base: \"{{ repo.base_branch }}\"`"
      assert template =~ "Confirm the resulting PR with `repo.change_proposal_snapshot`"
      assert template =~ "Do not call `repo-provider`, `gh`, or direct GitHub APIs for label handling"
      assert template =~ "supported branch, diff, commit, and push actions"
      assert template =~ "except for the workflow state transition described below"
      refute template =~ "Raw Linear GraphQL"
      refute template =~ "raw Linear GraphQL"
      refute template =~ "repo-provider pr-issue-comments"
      refute template =~ "repo-provider pr-review-comments"
      refute template =~ "repo-provider pr-reviews"
      refute template =~ "update script"
      refute template =~ "launch-app"
      refute template =~ "github-pr-media"
      refute template =~ "Add a short comment if state and issue content are inconsistent"
      refute template =~ "pr-add-label"
      refute template =~ "update_issue("
    end
  end

  test "Linear tracker skill is provider neutral about workpad headings" do
    skill = File.read!(linear_tracker_skill_path())

    assert skill =~ "WORKFLOW_WORKPAD_HEADING"
    assert skill =~ "This skill owns Linear tracker semantics"
    assert skill =~ "Workflow templates own when those actions are"
    assert skill =~ "heading is the stable comment identity"
    assert skill =~ "Linear Access Boundary"
    assert skill =~ "Only use inventory-listed typed Linear tools"
    assert skill =~ "Do not use any non-inventory Linear access path"
    refute skill =~ "direct Linear API"
    refute skill =~ "token-bearing shell"
    refute skill =~ "Claude Code Workpad"
    refute skill =~ "Codex Workpad"
    refute skill =~ "OpenCode Workpad"
    refute skill =~ "Raw Linear GraphQL"
    refute skill =~ "raw GraphQL"
  end

  test "TAPD workflow templates use typed tracker tools as the routine path" do
    for path <- tapd_template_paths() do
      assert {:ok, %{config: config, prompt: prompt}} = Workflow.load(path)

      assert get_in(config, ["workflow", "profile", "options", "requirements", "typed_tracker_tools"]) ==
               true

      assert get_in(config, ["workflow", "profile", "options", "requirements", "typed_repo_tools"]) ==
               true

      assert prompt =~ "{{ tool_inventory }}"
      assert prompt =~ "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/tapd/SKILL.md"
      assert Regex.match?(~r/Use inventory-listed typed\s+tracker tools for routine actions/, prompt)
      assert prompt =~ "Use inventory-listed repo-provider typed tools for routine PR"
      assert prompt =~ "tracker.create_follow_up_issue"
      assert prompt =~ "tracker.add_issue_relation"
      assert prompt =~ "tracker.save_issue_dependency"
      assert prompt =~ "tracker.provider_diagnostics"
      assert prompt =~ "repo.create_or_update_change_proposal"
      assert prompt =~ "repo.change_proposal_snapshot"
      assert prompt =~ "repo.read_change_proposal_discussion"
      assert prompt =~ "actionableItems"
      assert prompt =~ "unresolvedFeedbackSummary"
      assert prompt =~ "unresolvedFeedbackSummary.unresolvedItems"
      assert prompt =~ "nextResponseActions"
      assert prompt =~ "responseAction"
      assert prompt =~ "prefilledArguments"
      assert prompt =~ "requiredArguments"
      assert prompt =~ "repo_add_change_proposal_comment"
      assert prompt =~ "repo_reply_change_proposal_review_comment"
      assert prompt =~ "repo_commit.mode"
      assert prompt =~ "`all` or `staged`"
      assert prompt =~ "do not\nsend helper command names or aliases such as `stage_all`"
      assert prompt =~ "repo_checkout.mode"
      assert prompt =~ "`create_or_switch`, `create`, or `switch`"
      assert prompt =~ "Do not send helper-style aliases such as `create_working_branch`"
      assert prompt =~ "typed-tool response on the\n   original PR/thread"

      assert prompt =~
               "Do not rely only on a new PR, commit message, or workpad\n   note to close out human feedback."

      assert prompt =~ "workspace-root `.symphony-tapd-workpad.md`"
      assert prompt =~ "`../.symphony-tapd-workpad.md`"
      assert prompt =~ "Never create, stage, or commit `repo/.symphony-tapd-workpad.md`"
      assert prompt =~ "stable identity heading is `TAPD Workpad`"
      assert prompt =~ "## TAPD Workpad"
      assert prompt =~ "TAPD Access Boundary"
      assert length(Regex.scan(~r/^## TAPD Access Boundary$/m, prompt)) == 1
      assert prompt =~ "Only use inventory-listed typed TAPD tools"
      refute prompt =~ "passthrough"
      refute prompt =~ "Use `tapd_api` for TAPD reads and writes during this run"
      refute prompt =~ "The injected `tapd_api` tool must be available"
      refute prompt =~ "\"path\": \"/stories\""
      refute prompt =~ "\"path\": \"/comments\""
      refute prompt =~ "repo-provider pr-issue-comments"
      refute prompt =~ "repo-provider pr-review-comments"
      refute prompt =~ "repo-provider pr-reviews"
    end
  end

  test "only TAPD CNB templates opt into change-proposal reconciliation" do
    enabled_aliases =
      Templates.aliases()
      |> Enum.filter(fn template_alias ->
        {:ok, path} = Templates.resolve(template_alias)
        {:ok, %{config: config}} = Workflow.load(path)

        get_in(config, ["workflow", "reconciliation", "change_proposal", "enabled"]) == true
      end)
      |> Enum.sort()

    assert enabled_aliases == ["tapd/cnb/claude_code", "tapd/cnb/codebuddy_code", "tapd/cnb/opencode"]

    for template_alias <- enabled_aliases do
      {:ok, path} = Templates.resolve(template_alias)
      assert {:ok, %{config: config, prompt: prompt}} = Workflow.load(path)

      assert {:ok,
              %ReconciliationConfig{
                enabled?: true,
                candidate_discovery: :runtime_targeted,
                source_routes: [:review],
                ready_target_route: :merging,
                changes_requested_target_route: :rework,
                failed_checks_target_route: :rework,
                already_merged_target_route: :resolved,
                require_approval?: true,
                require_passing_checks?: true,
                require_mergeable?: true,
                failed_checks_confirmation_count: 2,
                max_processed_candidate_issues_per_cycle: 25
              }} = ReconciliationConfig.from_settings(config)

      assert prompt =~ "backend change-proposal reconciliation moves the story"
    end
  end

  test "TAPD tracker skill is typed-tool first" do
    skill = File.read!(tapd_tracker_skill_path())

    assert skill =~ "`tracker.issue_snapshot`"
    assert skill =~ "`tracker.move_issue`"
    assert skill =~ "`tracker.upsert_workpad`"
    assert skill =~ "`tracker.attach_change_proposal`"
    assert skill =~ "`tracker.create_follow_up_issue`"
    assert skill =~ "`tracker.add_issue_relation`"
    assert skill =~ "`tracker.save_issue_dependency`"
    assert skill =~ "`tracker.provider_diagnostics`"
    assert skill =~ "This skill owns TAPD tracker semantics"
    assert skill =~ "Workflow templates own when those actions are allowed"
    assert skill =~ "heading is the stable comment identity"
    assert skill =~ "Do not replace the\nheading with the first body section such as `### Plan`"
    assert skill =~ "TAPD Access Boundary"
    assert skill =~ "Only use inventory-listed typed TAPD tools"
    refute skill =~ "passthrough"
    refute skill =~ "dynamic_tool_exposure"
    refute skill =~ "\"method\": \"GET\""
    refute skill =~ "\"path\": \"/stories\""
  end

  defp runtime_reference_violations(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      @forbidden_runtime_references
      |> Enum.filter(fn {pattern, _label} -> Regex.match?(pattern, line) end)
      |> Enum.map(fn {_pattern, label} ->
        "#{Path.relative_to_cwd(path)}:#{line_number} references #{label}: #{String.trim(line)}"
      end)
    end)
  end

  defp provider_command_violations(path) do
    case Workflow.load(path) do
      {:ok, %{config: config}} ->
        config
        |> get_in(["agent_provider", "options", "command_argv"])
        |> provider_command_violation(path)

      {:error, reason} ->
        ["#{Path.relative_to_cwd(path)} failed to parse: #{inspect(reason)}"]
    end
  end

  defp provider_command_violation([command | _rest], path) when is_binary(command) do
    if Path.type(command) == :absolute do
      ["#{Path.relative_to_cwd(path)} uses an absolute provider command path: #{command}"]
    else
      []
    end
  end

  defp provider_command_violation(_command_argv, _path), do: []

  defp linear_github_template_paths do
    "../../priv/workflow_templates/linear/github/*.md"
    |> Path.expand(__DIR__)
    |> Path.wildcard()
  end

  defp linear_tracker_skill_path do
    Path.expand("../../priv/workspace_automation/skills/tracker/linear/SKILL.md", __DIR__)
  end

  defp tapd_template_paths do
    "../../priv/workflow_templates/tapd/**/*.md"
    |> Path.expand(__DIR__)
    |> Path.wildcard()
  end

  defp tapd_tracker_skill_path do
    Path.expand("../../priv/workspace_automation/skills/tracker/tapd/SKILL.md", __DIR__)
  end
end
