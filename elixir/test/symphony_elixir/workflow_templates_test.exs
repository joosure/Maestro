defmodule SymphonyElixir.WorkflowTemplatesTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.Config.Schema, as: ConfigSchema
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds
  alias SymphonyElixir.Tracker.Linear.WorkflowConfig, as: LinearWorkflowConfig
  alias SymphonyElixir.Tracker.Tapd.WorkflowConfig, as: TapdWorkflowConfig
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Capabilities, as: WorkflowCapabilities
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Profiles.Triage
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.TemplateRegistry
  alias SymphonyElixir.Workflow.Templates

  @partial_include_pattern ~r/^\s*<!--\s*symphony-include:\s*([^>]+?)\s*-->\s*$/
  @allowed_prompt_roots ~w(issue repo runtime workflow)
  @partial_dependency_phrases [
    "shared Workpad Contract",
    "extends the shared",
    "redefine workpad",
    "companion partial",
    "layered partial",
    "Step 1 and Step 2",
    "normal kickoff flow",
    "completion bar is satisfied"
  ]

  @forbidden_runtime_references [
    {Regex.compile!("(^|[^[:alnum:]_])(?:\\.\\./)?" <> ("spe" <> "cs") <> "/"), "repository-local private asset path"},
    {~r/\b[A-Za-z0-9_]+_spec\.md\b/, "spec markdown file"},
    {Regex.compile!("\\b" <> ("SP" <> "EC.md") <> "\\b"), "top-level private asset entrypoint"},
    {Regex.compile!("\\bintegration " <> "spec\\b", "i"), "runtime reference to private integration notes"},
    {~r|/Users/[^[:space:]"'`]+|, "local macOS user path"}
  ]
  @skill_owned_how_to_phrases [
    "Never pass `workspace_id`",
    "When querying or updating a Story, always use the full TAPD API `Story.id`",
    "using the full TAPD `Story.id`",
    "`repo.commit` mode is `all` or `staged`",
    "`repo.checkout` mode is `create_or_switch`, `create`, or `switch`",
    "pass the proposal description as a single string argument",
    "do not split Markdown sections into extra tool arguments"
  ]

  test "workflow and automation docs define the template skill runtime boundary" do
    workflow_readme = Templates.root() |> Path.join("README.md") |> File.read!()

    automation_readme =
      File.cwd!()
      |> Path.join("priv/workspace_automation/README.md")
      |> File.read!()

    for readme <- [workflow_readme, automation_readme] do
      normalized_readme = String.downcase(readme)

      assert normalized_readme =~ "workflow templates answer when the current issue should do work"
      assert normalized_readme =~ "bundled skills"
      assert normalized_readme =~ "runtime code and typed-tool schemas enforce"
    end

    assert workflow_readme =~
             "They should not restate detailed typed-tool argument schemas"

    assert automation_readme =~ "Skills should not redefine workflow routes"
    assert automation_readme =~ "completion bars, or tracker state"
  end

  test "bundled workflow templates are self-contained runtime guidance" do
    violations =
      Templates.paths()
      |> Enum.flat_map(&runtime_reference_violations/1)

    assert violations == []
  end

  test "concrete workflow templates do not restate skill-owned how-to details" do
    violations =
      Templates.paths()
      |> Enum.flat_map(&skill_owned_how_to_violations/1)

    assert violations == []
  end

  test "bundled workflow template provider commands use portable executable names" do
    violations =
      Templates.paths()
      |> Enum.flat_map(&provider_command_violations/1)

    assert violations == []
  end

  test "template aliases resolve with and without .md" do
    opencode_alias =
      TemplateRegistry.alias_for!(
        TrackerKinds.linear(),
        RepoProviderKinds.github(),
        AgentProviderKinds.opencode()
      )

    {:ok, opencode_path} = Templates.resolve(opencode_alias)
    {:ok, opencode_md_path} = Templates.resolve(opencode_alias <> ".md")

    assert opencode_path == opencode_md_path
    assert Path.basename(opencode_path) == "opencode.md"

    assert {:error, "Workflow template alias must point to a workflow template"} =
             Templates.resolve("README.zh-CN")

    assert {:error, "Workflow template alias must point to a workflow template"} =
             Templates.resolve("README.zh-CN")

    for template_alias <- Templates.aliases() do
      assert {:ok, _path} = Templates.resolve(template_alias)
    end

    refute Enum.any?(Templates.aliases(), &String.starts_with?(&1, "_partials/"))
  end

  test "local quickstart alias is a bundled workflow template" do
    assert Templates.local_quickstart_alias() == TemplateRegistry.local_quickstart_alias()
    assert Templates.local_quickstart_alias() in Templates.aliases()
    assert {:ok, _path} = Templates.resolve(Templates.local_quickstart_alias())
  end

  test "bundled workflow template registry covers concrete templates" do
    assert Enum.sort(TemplateRegistry.aliases()) == Enum.sort(Templates.aliases())
    assert Enum.sort(workflow_template_readme_aliases()) == Enum.sort(TemplateRegistry.aliases())

    assert {:ok, entry} = TemplateRegistry.fetch(TemplateRegistry.local_quickstart_alias())
    assert entry.tracker_kind == TrackerKinds.memory()
    assert entry.repo_provider_kind == RepoProviderKinds.memory()
    assert entry.agent_provider_kind == AgentProviderKinds.mock()
    assert {:ok, ^entry} = TemplateRegistry.fetch(TemplateRegistry.local_quickstart_alias() <> ".md")

    assert TemplateRegistry.alias_for!(
             TrackerKinds.linear(),
             RepoProviderKinds.github(),
             AgentProviderKinds.opencode()
           ) in Templates.aliases()
  end

  test "bundled workflow template registry matches front matter structure" do
    for entry <- TemplateRegistry.entries() do
      assert {:ok, path} = Templates.resolve(entry.template_alias)
      assert {:ok, %{config: config}} = Workflow.load(path)

      assert get_in(config, ["workflow", "profile", "kind"]) == entry.profile_kind
      assert get_in(config, ["workflow", "profile", "version"]) == entry.profile_version
      assert get_in(config, ["tracker", "kind"]) == entry.tracker_kind
      assert get_in(config, ["repo", "provider", "kind"]) == entry.repo_provider_kind
      assert get_in(config, ["agent_provider", "kind"]) == entry.agent_provider_kind
      assert get_in(config, ["agent_provider", "options", "credential_ref"]) == entry.credential_ref
    end
  end

  test "bundled workflow templates map profile route keys to owned lifecycle phases" do
    for entry <- TemplateRegistry.entries() do
      assert {:ok, path} = Templates.resolve(entry.template_alias)
      assert {:ok, %{config: config}} = Workflow.load(path)
      assert {:ok, settings} = ConfigSchema.parse(config)

      profile_module = ProfileRegistry.fetch!(entry.profile_kind, entry.profile_version)
      effective_workflow = effective_template_workflow!(settings, entry.tracker_kind, profile_module)
      state_phase_map = effective_workflow.state_phase_map
      raw_state_by_route_key = effective_workflow.raw_state_by_route_key
      expected_phase_by_route_key = profile_module.lifecycle_phase_by_route_key()

      assert effective_workflow.profile_kind == entry.profile_kind
      assert effective_workflow.profile_version == entry.profile_version
      assert Enum.sort(Map.keys(expected_phase_by_route_key)) == Enum.sort(profile_module.route_keys())

      for route_key <- profile_module.route_keys() do
        raw_state = RoutePolicy.raw_state_for_route_key(raw_state_by_route_key, route_key)
        expected_phase = Map.fetch!(expected_phase_by_route_key, route_key)

        assert WorkflowLifecycle.valid_phase?(expected_phase)
        assert WorkflowLifecycle.phase_for_state(raw_state, state_phase_map) == expected_phase
      end
    end
  end

  test "bundled templates do not duplicate profile-owned default route policy" do
    for entry <- TemplateRegistry.entries() do
      assert {:ok, path} = Templates.resolve(entry.template_alias)
      assert {:ok, %{config: config}} = Workflow.load(path)

      configured_policy = get_in(config, ["tracker", "lifecycle", "policy_by_route_key"])

      if is_map(configured_policy) and map_size(configured_policy) > 0 do
        {:ok, profile_context} =
          ProfileRegistry.resolve(%{
            "kind" => entry.profile_kind,
            "version" => entry.profile_version,
            "options" => get_in(config, ["workflow", "profile", "options"]) || %{}
          })

        default_policy =
          ProfileRegistry.default_policy_by_route_key(profile_context.module, profile_context.options)

        resolved_policy =
          RoutePolicy.resolve_policy_by_route_key(
            configured_policy,
            default_policy,
            profile_context.module
          )

        refute resolved_policy == default_policy,
               "#{entry.template_alias} repeats the selected profile's default route policy"
      end
    end
  end

  test "external workflow template defaults stay aligned with registry" do
    assert compose_quickstart_template() == TemplateRegistry.local_quickstart_alias()

    assert compose_integration_templates() == %{
             "symphony-opencode" => provider_template_default("SYMPHONY_OPENCODE_TEMPLATE", linear_github_opencode_template_alias()),
             "symphony-codex" => provider_template_default("SYMPHONY_CODEX_TEMPLATE", linear_github_codex_template_alias()),
             "symphony-claude-code" => provider_template_default("SYMPHONY_CLAUDE_CODE_TEMPLATE", linear_github_claude_code_template_alias()),
             "symphony-codebuddy" => provider_template_default("SYMPHONY_CODEBUDDY_TEMPLATE", tapd_cnb_codebuddy_template_alias())
           }

    env_example = env_file_values(repo_path(".env.example"))

    assert env_example["SYMPHONY_OPENCODE_TEMPLATE"] == linear_github_opencode_template_alias()
    assert env_example["SYMPHONY_CODEX_TEMPLATE"] == linear_github_codex_template_alias()
    assert env_example["SYMPHONY_CLAUDE_CODE_TEMPLATE"] == linear_github_claude_code_template_alias()
    assert env_example["SYMPHONY_CODEBUDDY_TEMPLATE"] == tapd_cnb_codebuddy_template_alias()

    assert script_template_default(repo_path("scripts/linear-workflow-init")) == linear_github_opencode_template_alias()
    assert script_template_default(repo_path("scripts/tapd-workflow-init")) == tapd_cnb_codebuddy_template_alias()
  end

  test "all bundled workflow template aliases load after partial expansion" do
    for template_alias <- Templates.aliases() do
      assert {:ok, path} = Templates.resolve(template_alias)

      assert {:ok, %{config: config, prompt: prompt, prompt_template: prompt_template}} =
               Workflow.load(path)

      assert is_map(config)
      assert is_binary(prompt)
      assert prompt == prompt_template
      refute prompt =~ "symphony-include:"
    end
  end

  test "workflow prompt templates only use approved top-level context roots" do
    violations =
      (Templates.paths() ++ partial_paths())
      |> Enum.flat_map(&prompt_root_violations/1)

    assert violations == []
  end

  test "workflow render task can include source front matter with expanded prompt body" do
    Mix.Task.clear()
    codebuddy_template_alias = tapd_cnb_codebuddy_template_alias()

    default_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.run("symphony.workflow.render", [codebuddy_template_alias])
      end)

    assert default_output =~ "You are working on a TAPD story"
    assert default_output =~ "## Critical Execution Summary"
    refute default_output =~ "symphony-include:"
    refute String.starts_with?(default_output, "---\n")

    Mix.Task.clear()

    full_output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.run("symphony.workflow.render", [
          "--with-front-matter-source",
          codebuddy_template_alias
        ])
      end)

    assert String.starts_with?(full_output, "---\nworkflow:")

    assert full_output =~
             "# Workflow Core resolves this profile before tracker route-map validation."

    assert full_output =~ "\n---\n\nYou are working on a TAPD story"
    assert full_output =~ "## Critical Execution Summary"
    refute full_output =~ "symphony-include:"
  end

  test "workflow template partial includes are explicit existing files under _partials" do
    violations =
      Templates.paths()
      |> Enum.flat_map(fn path ->
        path
        |> include_refs()
        |> Enum.flat_map(fn {line_number, partial_ref} ->
          validate_workflow_partial_ref(path, line_number, partial_ref)
        end)
      end)

    assert violations == []
  end

  test "workflow partials do not include other partials" do
    violations =
      partial_paths()
      |> Enum.flat_map(fn path ->
        path
        |> include_refs()
        |> Enum.map(fn {line_number, partial_ref} ->
          "#{Path.relative_to_cwd(path)}:#{line_number} includes #{inspect(partial_ref)}"
        end)
      end)

    assert violations == []
  end

  test "workflow partials are standalone fragments without implicit companion dependencies" do
    violations =
      partial_paths()
      |> Enum.flat_map(fn path ->
        content = File.read!(path)

        dependency_phrase_violations(path, content) ++
          ordered_list_start_violations(path, content)
      end)

    assert violations == []
  end

  test "workflow partials do not provide their own section headings" do
    violations =
      partial_paths()
      |> Enum.flat_map(fn path ->
        path
        |> markdown_headings_outside_fences()
        |> Enum.map(fn {line_number, line} ->
          "#{Path.relative_to_cwd(path)}:#{line_number} has section heading inside partial: #{String.trim(line)}"
        end)
      end)

    assert violations == []
  end

  test "workflow workpad contract partials are self-contained per tracker" do
    violations =
      Templates.paths()
      |> Enum.flat_map(fn path ->
        workpad_contract_refs =
          path
          |> include_refs()
          |> Enum.map(fn {_line_number, partial_ref} -> partial_ref end)
          |> Enum.filter(&String.ends_with?(&1, "_workpad_storage_notes.md"))

        if length(workpad_contract_refs) > 1 do
          [
            "#{Path.relative_to_cwd(path)} includes multiple workpad contract partials: #{Enum.join(workpad_contract_refs, ", ")}"
          ]
        else
          []
        end
      end)

    assert violations == []

    refute File.exists?(Path.join(Templates.root(), "_partials/workpad_contract.md"))

    for partial_ref <- [
          "_partials/tracker/linear_workpad_storage_notes.md",
          "_partials/tracker/tapd_workpad_contract.md"
        ] do
      partial = Templates.root() |> Path.join(partial_ref) |> File.read!()

      assert partial =~
               "The workpad stable identity is the typed-tool returned `workpad.id` / `workpad_id`"

      assert partial =~ "Agents must read workpad identity through `tracker.issue_snapshot`"
      assert partial =~ "Agents must update workpad only through `tracker.upsert_workpad`"

      assert partial =~
               "Agents must not identify workpads by title, Markdown shape, comment body, or provider UI text"
    end
  end

  test "OpenCode template uses the ZAI model without managed credential lease" do
    {:ok, opencode_path} = Templates.resolve(linear_github_opencode_template_alias())
    assert {:ok, %{config: config}} = Workflow.load(opencode_path)

    options = get_in(config, ["agent_provider", "options"])

    assert options["model"] == "zai-coding-plan/glm-5.1"
    refute Map.has_key?(options, "credential_ref")
  end

  test "memory mock template provides a no-credential local workflow" do
    {:ok, template_path} = Templates.resolve(Templates.local_quickstart_alias())
    assert {:ok, %{config: config, prompt: prompt}} = Workflow.load(template_path)
    assert {:ok, settings} = SymphonyElixir.Config.Schema.parse(config)

    assert settings.workflow.profile["kind"] == Triage.kind()
    assert settings.tracker.kind == TrackerKinds.memory()
    assert settings.repo.provider.kind == RepoProviderKinds.memory()
    assert settings.agent_provider.kind == AgentProviderKinds.mock()
    assert settings.agent_provider.options["complete_issue_state"] == "routed"

    assert :ok = SymphonyElixir.Tracker.validate_config(settings.tracker)
    assert :ok = SymphonyElixir.RepoProvider.validate_config(settings.repo)
    assert :ok = SymphonyElixir.AgentProvider.validate_config(settings.agent_provider)

    available_capabilities = SymphonyElixir.Config.Capabilities.available_capabilities(settings)

    assert :ok =
             WorkflowCapabilities.validate_required_capabilities(settings, available_capabilities)

    assert {:ok, [issue]} = SymphonyElixir.Tracker.fetch_candidate_issues(settings.tracker)
    assert issue.identifier == "MEM-1"
    assert issue.state == "classifying"

    assert prompt =~ "No external tracker"
    assert prompt =~ "mock agent provider"
  end

  test "OpenCode template prevents incomplete repo work from entering review" do
    {:ok, opencode_path} = Templates.resolve(linear_github_opencode_template_alias())
    assert {:ok, %{prompt: template}} = Workflow.load(opencode_path)

    assert template =~ "`repo/` is a workspace-relative path, not an absolute filesystem path"
    assert template =~ "Never\n  read from or write to `/repo`"
    assert template =~ "A failed read/write under `/repo/...` is a path-selection error"
    assert template =~ "Retry with workspace-relative `repo/...`"

    assert template =~
             "Missing commits, no diff, or a PR-create failure caused by no branch changes\n  is incomplete execution"

    assert template =~ "Completion bar before review handoff"

    assert template =~
             "Do not move to `{{ issue.workflow.raw_state_by_route_key.review }}` unless the `Completion bar before review handoff` is satisfied"

    assert template =~
             "change proposal evidence is recorded through the typed tracker attach tool"
  end

  test "Linear lifecycle prompts use workflow raw-state facts instead of fixed Linear state names" do
    for path <- linear_github_template_paths() do
      assert {:ok, %{prompt: template}} = Workflow.load(path)

      assert template =~ "{{ issue.workflow.raw_state_by_route_key.planning }}"
      assert template =~ "{{ issue.workflow.raw_state_by_route_key.developing }}"
      assert template =~ "{{ issue.workflow.raw_state_by_route_key.review }}"
      assert template =~ "{{ issue.workflow.raw_state_by_route_key.merging }}"
      assert template =~ "{{ issue.workflow.raw_state_by_route_key.rework }}"
      assert template =~ "{{ issue.workflow.raw_state_by_route_key.resolved }}"

      refute template =~ "`Todo`"
      refute template =~ "`In Progress`"
      refute template =~ "`In Review`"
      refute template =~ "`Merging`"
      refute template =~ "`Rework`"
      refute template =~ "`Done`"
    end
  end

  test "Linear GitHub templates route state changes through typed tracker tools" do
    for path <- linear_github_template_paths() do
      assert {:ok, %{prompt: template}} = Workflow.load(path)

      assert template =~
               "Use the inventory `tracker.move_issue` typed tool to move the issue to `{{ issue.workflow.raw_state_by_route_key.developing }}`"

      assert template =~ "Linear Access Boundary"
      assert template =~ "Only use inventory-listed typed Linear tools"
      assert template =~ "do not use any non-inventory Linear access path"
      assert template =~ "## Linear Workpad Contract"

      assert template =~
               "The workpad stable identity is the typed-tool returned `workpad.id` / `workpad_id`"

      assert template =~
               "Agents must not identify workpads by title, Markdown shape, comment body, or provider UI text"

      assert template =~
               "If the snapshot includes a workpad `workpad_id`, pass that id to `tracker.upsert_workpad` on updates"

      assert template =~
               "Fetch the issue by explicit ticket ID through the inventory `tracker.issue_snapshot` typed tool"

      assert template =~
               "Use the inventory `tracker.issue_snapshot` typed tool with comments included"

      assert template =~ "through the inventory `tracker.upsert_workpad` typed tool"

      assert template =~
               "Record a short note in the workpad if state and issue content are inconsistent"

      refute template =~ "direct Linear API"
      refute template =~ "token-bearing shell"
      assert template =~ "This workflow defines when tracker actions are allowed"
      assert template =~ "If a required feedback capability is missing from the inventory"
      assert template =~ "unresolvedFeedbackSummary.unresolvedItems"
      assert template =~ "nextResponseActions"
      assert template =~ "tracker.upsert_workpad"
      assert template =~ "tracker.attach_change_proposal"

      assert template =~
               "If it is missing, stop as blocked and record the missing typed tracker capability"

      assert template =~ "target repository's documented launch or runtime validation"

      assert template =~
               "change proposal evidence is recorded through the typed tracker attach tool"

      assert template =~ "follow the inventory schema exactly"
      assert template =~ "do not pass helper command names or aliases as typed-tool arguments"
      refute template =~ "`repo.commit` mode is `all` or `staged`"
      refute template =~ "`repo.checkout` mode is `create_or_switch`, `create`, or `switch`"
      assert template =~ "repo.change_proposal_snapshot"

      assert template =~
               "Create or update the PR through the inventory `repo.create_or_update_change_proposal` typed tool"

      assert template =~
               "For a new PR, pass `mode: \"create\"`, `title`, `base: \"{{ repo.base_branch }}\"`"

      assert template =~ "Confirm the resulting PR with `repo.change_proposal_snapshot`"

      assert template =~ "do not use separate GitHub label commands"

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

  test "Linear tracker skill uses typed workpad identity" do
    skill = File.read!(linear_tracker_skill_path())

    assert skill =~ "This skill owns Linear tracker semantics"
    assert skill =~ "Workflow templates own when those actions are"
    assert skill =~ "Use `workpad_id` as the workpad identity"
    assert skill =~ "readable content only"
    assert skill =~ "Linear Access Boundary"
    assert skill =~ "Only use inventory-listed typed Linear tools"
    assert skill =~ "Do not use any non-inventory Linear access path"
    refute skill =~ "WORKFLOW_WORKPAD_HEADING"
    refute skill =~ "heading is the stable comment identity"
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

      assert get_in(config, [
               "workflow",
               "profile",
               "options",
               "requirements",
               "typed_tracker_tools"
             ]) ==
               true

      assert get_in(config, ["workflow", "profile", "options", "requirements", "typed_repo_tools"]) ==
               true

      assert prompt =~ "{{ runtime.tool_inventory }}"
      assert prompt =~ "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/tapd/SKILL.md"

      assert Regex.match?(
               ~r/Use inventory-listed typed\s+tracker tools for routine actions/,
               prompt
             )

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
      assert prompt =~ "typed-tool response on the original PR/thread"

      assert prompt =~
               "Do not rely only on a new PR, commit message, or workpad note to close out human feedback."

      assert prompt =~ "workspace-root `.symphony-tapd-workpad.md`"
      assert prompt =~ "`../.symphony-tapd-workpad.md`"
      assert prompt =~ "Never create, stage, or commit `repo/.symphony-tapd-workpad.md`"
      assert prompt =~ "## TAPD Workpad Contract"

      assert prompt =~
               "The workpad stable identity is the typed-tool returned `workpad.id` / `workpad_id`"

      assert prompt =~
               "Agents must not identify workpads by title, Markdown shape, comment body, or provider UI text"

      assert prompt =~ "do not search comments by title or Markdown shape yourself"
      assert prompt =~ "## Workpad"
      assert prompt =~ "TAPD Access And Tools"
      assert length(Regex.scan(~r/^## TAPD Access And Tools$/m, prompt)) == 1
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

    assert enabled_aliases ==
             Enum.sort([
               tapd_cnb_claude_code_template_alias(),
               tapd_cnb_codebuddy_template_alias(),
               tapd_cnb_opencode_template_alias()
             ])

    for template_alias <- enabled_aliases do
      {:ok, path} = Templates.resolve(template_alias)
      assert {:ok, %{config: config, prompt: prompt}} = Workflow.load(path)

      assert {:ok, reconciliation_config} = ReconciliationConfig.from_settings(config)
      assert reconciliation_config.enabled? == true
      assert reconciliation_config.candidate_discovery == :runtime_targeted
      assert reconciliation_config.source_routes == [coding_route_ref(:review)]

      assert reconciliation_config.outcome_routes == %{
               ready: coding_route_ref(:merging),
               changes_requested: coding_route_ref(:rework),
               failed_checks: coding_route_ref(:rework),
               already_merged: coding_route_ref(:resolved)
             }

      assert reconciliation_config.require_approval? == true
      assert reconciliation_config.require_passing_checks? == true
      assert reconciliation_config.require_mergeable? == true
      assert reconciliation_config.failed_checks_confirmation_count == 2
      assert reconciliation_config.max_processed_candidate_issues_per_cycle == 25

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
    assert skill =~ "Use `workpad_id` as the workpad identity"
    assert skill =~ "readable content only"
    assert skill =~ "TAPD Access Boundary"
    assert skill =~ "Only use inventory-listed typed TAPD tools"
    refute skill =~ "heading is the stable comment identity"
    refute skill =~ "TAPD Workpad"
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

  defp skill_owned_how_to_violations(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      @skill_owned_how_to_phrases
      |> Enum.filter(&String.contains?(line, &1))
      |> Enum.map(fn phrase ->
        "#{Path.relative_to_cwd(path)}:#{line_number} restates skill/schema-owned how-to #{inspect(phrase)}"
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

  defp prompt_root_violations(path) do
    path
    |> liquid_root_refs()
    |> Enum.reject(fn {_line_number, root, _line} -> root in @allowed_prompt_roots end)
    |> Enum.map(fn {line_number, root, line} ->
      "#{Path.relative_to_cwd(path)}:#{line_number} uses unsupported top-level prompt root #{inspect(root)}: #{line}"
    end)
  end

  defp liquid_root_refs(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      line
      |> root_refs_from_line()
      |> Enum.map(fn root -> {line_number, root, String.trim(line)} end)
    end)
  end

  defp root_refs_from_line(line) when is_binary(line) do
    [
      ~r/\{\{\s*([A-Za-z_][A-Za-z0-9_]*)/,
      ~r/\{%\s*if\s+([A-Za-z_][A-Za-z0-9_]*)/,
      ~r/\{%\s*unless\s+([A-Za-z_][A-Za-z0-9_]*)/,
      ~r/\{%\s*for\s+\w+\s+in\s+([A-Za-z_][A-Za-z0-9_]*)/
    ]
    |> Enum.flat_map(&Regex.scan(&1, line, capture: :all_but_first))
    |> List.flatten()
    |> Enum.uniq()
  end

  defp include_refs(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      case Regex.run(@partial_include_pattern, line, capture: :all_but_first) do
        [partial_ref] -> [{line_number, String.trim(partial_ref)}]
        _no_include -> []
      end
    end)
  end

  defp validate_workflow_partial_ref(path, line_number, partial_ref) do
    location = "#{Path.relative_to_cwd(path)}:#{line_number}"
    partial_segments = Path.split(partial_ref)

    cond do
      partial_ref == "" ->
        ["#{location} uses a blank partial include"]

      Path.type(partial_ref) == :absolute ->
        ["#{location} uses an absolute partial include: #{partial_ref}"]

      Enum.any?(partial_segments, &(&1 in [".", ".."])) ->
        ["#{location} uses a partial include with traversal: #{partial_ref}"]

      Path.extname(partial_ref) != ".md" ->
        ["#{location} uses a non-Markdown partial include: #{partial_ref}"]

      not String.starts_with?(partial_ref, "_partials/") ->
        ["#{location} includes outside _partials/: #{partial_ref}"]

      not File.regular?(Path.join(Templates.root(), partial_ref)) ->
        ["#{location} includes a missing partial: #{partial_ref}"]

      true ->
        []
    end
  end

  defp partial_paths do
    Templates.root()
    |> Path.join("_partials/**/*.md")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp markdown_headings_outside_fences(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({false, []}, fn {line, line_number}, {in_fence?, violations} ->
      cond do
        Regex.match?(~r/^\s*(```|~~~)/, line) ->
          {not in_fence?, violations}

        not in_fence? and Regex.match?(~r/^\#{1,6}\s+/, line) ->
          {in_fence?, [{line_number, line} | violations]}

        true ->
          {in_fence?, violations}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp dependency_phrase_violations(path, content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      @partial_dependency_phrases
      |> Enum.filter(&String.contains?(line, &1))
      |> Enum.map(fn phrase ->
        "#{Path.relative_to_cwd(path)}:#{line_number} uses dependency phrase #{inspect(phrase)}"
      end)
    end)
  end

  defp ordered_list_start_violations(path, content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.find_value(fn {line, line_number} ->
      case Regex.run(~r/^\s*(\d+)\.\s+/, line, capture: :all_but_first) do
        ["1"] -> {:ok, :starts_at_one}
        [number] -> {line_number, number}
        _no_ordered_item -> nil
      end
    end)
    |> case do
      nil ->
        []

      {:ok, :starts_at_one} ->
        []

      {line_number, number} ->
        [
          "#{Path.relative_to_cwd(path)}:#{line_number} starts ordered list at #{number}; partial ordered lists must be self-contained"
        ]
    end
  end

  defp linear_github_template_paths do
    "../../priv/workflow_templates/linear/github/*.md"
    |> Path.expand(__DIR__)
    |> Path.wildcard()
  end

  defp effective_template_workflow!(settings, tracker_kind, profile_module) do
    cond do
      tracker_kind == TrackerKinds.linear() ->
        LinearWorkflowConfig.global_workflow(settings.tracker)

      tracker_kind == TrackerKinds.tapd() ->
        TapdWorkflowConfig.global_workflow(settings.tracker)

      tracker_kind == TrackerKinds.memory() ->
        profile_context = ProfileRegistry.resolve!(settings.workflow.profile)
        lifecycle = settings.tracker.lifecycle || %{}

        %{
          workitem_type_id: nil,
          active_states: Map.get(lifecycle, "active_states", []),
          terminal_states: Map.get(lifecycle, "terminal_states", []),
          state_phase_map: Map.get(lifecycle, "state_phase_map", %{}),
          raw_state_by_route_key: RoutePolicy.identity_raw_state_by_route_key(profile_module),
          policy_by_route_key: profile_module.default_policy_by_route_key(),
          profile: %{kind: profile_context.kind, version: profile_context.version, options: profile_context.options},
          profile_kind: profile_context.kind,
          profile_version: profile_context.version,
          profile_options: profile_context.options,
          allowed_execution_profiles: profile_module.allowed_execution_profiles(profile_context.options),
          completion_contract: profile_module.completion_contract(profile_context.options),
          required_capabilities: profile_module.required_capabilities(profile_context.options),
          optional_capabilities: profile_module.optional_capabilities(profile_context.options)
        }
        |> SymphonyElixir.Workflow.Effective.new!()

      true ->
        flunk("unsupported bundled tracker kind for workflow template contract: #{inspect(tracker_kind)}")
    end
  end

  defp linear_github_opencode_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.opencode()
    )
  end

  defp linear_github_codex_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.codex()
    )
  end

  defp linear_github_claude_code_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.claude_code()
    )
  end

  defp linear_tracker_skill_path do
    Path.expand("../../priv/workspace_automation/skills/tracker/linear/SKILL.md", __DIR__)
  end

  defp tapd_template_paths do
    "../../priv/workflow_templates/tapd/**/*.md"
    |> Path.expand(__DIR__)
    |> Path.wildcard()
  end

  defp tapd_cnb_opencode_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.tapd(),
      RepoProviderKinds.cnb(),
      AgentProviderKinds.opencode()
    )
  end

  defp tapd_cnb_codebuddy_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.tapd(),
      RepoProviderKinds.cnb(),
      AgentProviderKinds.codebuddy_code()
    )
  end

  defp tapd_cnb_claude_code_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.tapd(),
      RepoProviderKinds.cnb(),
      AgentProviderKinds.claude_code()
    )
  end

  defp tapd_tracker_skill_path do
    Path.expand("../../priv/workspace_automation/skills/tracker/tapd/SKILL.md", __DIR__)
  end

  defp compose_quickstart_template do
    repo_path("deploy/compose/compose.quickstart.yml")
    |> yaml_file!()
    |> get_in(["services", "symphony", "environment", "SYMPHONY_TEMPLATE"])
  end

  defp compose_integration_templates do
    compose = yaml_file!(repo_path("deploy/compose/compose.integration.yml"))

    Map.new(
      ~w(symphony-opencode symphony-codex symphony-claude-code symphony-codebuddy),
      fn service ->
        {service, get_in(compose, ["services", service, "environment", "SYMPHONY_TEMPLATE"])}
      end
    )
  end

  defp provider_template_default(env_name, template_alias), do: "${#{env_name}:-#{template_alias}}"

  defp coding_route_ref(route_key) do
    %RouteRef{profile_kind: "coding_pr_delivery", profile_version: 1, route_key: route_key}
  end

  defp yaml_file!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, value} -> value
      {:error, reason} -> flunk("failed to parse #{Path.relative_to_cwd(path)}: #{inspect(reason)}")
    end
  end

  defp env_file_values(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" or String.starts_with?(line, "#") ->
          acc

        String.contains?(line, "=") ->
          [key, value] = String.split(line, "=", parts: 2)
          Map.put(acc, String.trim(key), String.trim(value))

        true ->
          acc
      end
    end)
  end

  defp script_template_default(path) do
    content = File.read!(path)

    case Regex.run(~r/parser\.add_argument\(\s*"--template".*?default="([^"]+)"/s, content, capture: :all_but_first) do
      [template_alias] ->
        template_alias

      _no_default ->
        flunk("missing --template default in #{Path.relative_to_cwd(path)}")
    end
  end

  defp repo_path(relative_path) do
    Path.expand(Path.join(["..", "..", "..", relative_path]), __DIR__)
  end

  defp workflow_template_readme_aliases do
    readme = Templates.root() |> Path.join("README.md") |> File.read!()

    case Regex.run(~r/Current aliases:\n\n```text\n(?<aliases>.*?)\n```/s, readme, capture: ["aliases"]) do
      [aliases] ->
        aliases
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _missing_aliases ->
        flunk("workflow template README is missing its Current aliases block")
    end
  end
end
