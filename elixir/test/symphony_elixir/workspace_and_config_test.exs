defmodule SymphonyElixir.WorkspaceAndConfigTest do
  use SymphonyElixir.TestSupport

  alias Ecto.Changeset
  alias SymphonyElixir.AgentProvider.Codex.Settings, as: CodexSettings
  alias SymphonyElixir.AgentProvider.Codex.Settings.StringOrMap
  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Config.Schema.StateLimits
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Events, as: OrchestratorEvents
  alias SymphonyElixir.Orchestrator.Runtime, as: OrchestratorRuntime
  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Error, as: TrackerError
  alias SymphonyElixir.Tracker.Linear.Adapter, as: LinearAdapter
  alias SymphonyElixir.Tracker.Linear.Client
  alias SymphonyElixir.Tracker.Linear.IssueReader
  alias SymphonyElixir.Tracker.Linear.Normalizer
  alias SymphonyElixir.Tracker.Linear.Pagination
  alias SymphonyElixir.Tracker.Linear.WorkflowConfig, as: LinearWorkflowConfig
  alias SymphonyElixir.Workflow.IssueContext

  defmodule LimitedRepoProviderAdapter do
    @behaviour SymphonyElixir.RepoProvider.Adapter

    def kind, do: "limited"
    def defaults, do: %{}
    def validate_config(_repo), do: :ok
    def capabilities, do: []
  end

  defmodule MissingTypedToolTrackerAdapter do
    @behaviour SymphonyElixir.Tracker.Adapter

    def kind, do: "missing_typed_tool_tracker"
    def defaults, do: %{}
    def validate_config(_tracker), do: :ok

    def capabilities do
      [
        "tracker.issue.read",
        "tracker.issue.update",
        "tracker.comment.read",
        "tracker.comment.write",
        "tracker.state.update",
        "tracker.issue_snapshot",
        "tracker.move_issue",
        "tracker.upsert_workpad"
      ]
    end

    def dynamic_tools(_tracker), do: []
  end

  defmodule RawFallbackToolTrackerAdapter do
    @behaviour SymphonyElixir.Tracker.Adapter

    def kind, do: "raw_fallback_tool_tracker"
    def defaults, do: %{}
    def validate_config(_tracker), do: :ok

    def capabilities do
      [
        "tracker.issue.read",
        "tracker.issue.update",
        "tracker.comment.read",
        "tracker.comment.write",
        "tracker.state.update",
        "tracker.issue_snapshot",
        "tracker.move_issue",
        "tracker.upsert_workpad"
      ]
    end

    def dynamic_tools(_tracker) do
      [
        %{
          "name" => "legacy_tracker_api",
          "description" => "Execute legacy tracker API.",
          "inputSchema" => %{"type" => "object"},
          "schemaVersion" => "1",
          "sideEffect" => "destructive",
          "sourceKind" => "legacy_tracker",
          "riskFlags" => ["external_network", "privileged_api"]
        }
      ]
    end
  end

  defmodule ShipWithoutMergeExecutionProfile do
    @behaviour SymphonyElixir.Workflow.ExecutionProfile

    def supported_actions, do: [:dispatch]
    def required_capabilities, do: []
  end

  defmodule WaitOnlyExecutionProfile do
    @behaviour SymphonyElixir.Workflow.ExecutionProfile

    def supported_actions, do: [:wait]
    def required_capabilities, do: []
  end

  defmodule ShipWithMergeExecutionProfile do
    @behaviour SymphonyElixir.Workflow.ExecutionProfile

    def supported_actions, do: [:dispatch]
    def required_capabilities, do: ["repo_provider.merge"]
  end

  defmodule TriageDispatchExecutionProfile do
    @behaviour SymphonyElixir.Workflow.ExecutionProfile

    def supported_actions, do: [:dispatch]
    def required_capabilities, do: []
  end

  defmodule MissingRequiredCapabilitiesExecutionProfile do
    def supported_actions, do: [:dispatch]
  end

  defmodule DuckTypedExecutionProfile do
    def supported_actions, do: [:dispatch]
    def required_capabilities, do: []
  end

  test "workspace bootstrap can be implemented in after_create hook" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-hook-bootstrap-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")

      File.mkdir_p!(template_repo)
      File.mkdir_p!(Path.join(template_repo, "keep"))
      File.write!(Path.join([template_repo, "keep", "file.txt"]), "keep me")
      File.write!(Path.join(template_repo, "README.md"), "hook clone\n")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md", "keep/file.txt"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "git clone --depth 1 #{template_repo} repo"
      )

      assert {:ok, workspace} = Workspace.create_for_issue("S-1")
      assert File.exists?(Path.join([workspace, "repo", ".git"]))
      assert File.read!(Path.join([workspace, "repo", "README.md"])) == "hook clone\n"
      assert File.read!(Path.join([workspace, "repo", "keep", "file.txt"])) == "keep me"
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace bootstraps bundled root .codex before after_create and keeps repo-local .codex isolated" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-codex-bootstrap-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: """
        [ -n "$SYMPHONY_WORKSPACE_AUTOMATION_DIR" ]
        [ "$SYMPHONY_WORKSPACE_AUTOMATION_DIR" = "$PWD/.codex" ]
        [ -f "$SYMPHONY_WORKSPACE_AUTOMATION_DIR/skills/repo/land/SKILL.md" ]
        printf '%s\\n' "$SYMPHONY_WORKSPACE_AUTOMATION_DIR" > automation-dir.txt
        [ -f .codex/skills/repo/land/SKILL.md ]
        [ -f .codex/bin/repo ]
        [ -f .codex/bin/repo-provider ]
        [ -f .codex/worktree_init.sh ]
        mkdir -p repo/.codex
        printf 'repo skill\\n' > repo/.codex/SKILL.md
        """
      )

      assert {:ok, workspace} = Workspace.create_for_issue("S-BOOT")
      assert File.read!(Path.join([workspace, "repo", ".codex", "SKILL.md"])) == "repo skill\n"
      assert File.exists?(Path.join([workspace, ".codex", "worktree_init.sh"]))
      assert File.exists?(Path.join([workspace, ".codex", "bin", "repo"]))
      assert File.exists?(Path.join([workspace, ".codex", "bin", "repo-provider"]))
      assert executable?(Path.join([workspace, ".codex", "bin", "repo"]))
      assert executable?(Path.join([workspace, ".codex", "bin", "repo-provider"]))
      assert File.read!(Path.join(workspace, "automation-dir.txt")) == Path.join(workspace, ".codex") <> "\n"

      assert {:ok, bundled_dir} = SymphonyElixir.Workspace.AutomationPack.bundled_source_dir()
      assert Path.basename(bundled_dir) == "workspace_automation"

      assert File.read!(Path.join([workspace, ".codex", "skills", "repo", "land", "SKILL.md"])) ==
               File.read!(Path.join([bundled_dir, "skills", "repo", "land", "SKILL.md"]))
    after
      File.rm_rf(test_root)
    end
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _other -> false
    end
  end

  test "workspace bootstraps root .codex only once per workspace" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-codex-copy-once-#{System.unique_integer([:positive])}"
      )

    try do
      automation_pack = Path.join([test_root, "automation", ".codex"])
      workspace_root = Path.join(test_root, "workspaces")
      source_skill = Path.join([automation_pack, "skills", "repo", "land", "SKILL.md"])

      File.mkdir_p!(Path.join([automation_pack, "skills", "repo", "land"]))
      File.write!(source_skill, "# source v1\n")

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        workspace_bootstrap_automation_from: automation_pack
      )

      assert {:ok, workspace} = Workspace.create_for_issue("S-ONCE")

      workspace_skill = Path.join([workspace, ".codex", "skills", "repo", "land", "SKILL.md"])
      File.write!(workspace_skill, "# workspace changed\n")
      File.write!(source_skill, "# source v2\n")

      assert {:ok, ^workspace} = Workspace.create_for_issue("S-ONCE")
      assert File.read!(workspace_skill) == "# workspace changed\n"
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace bootstrap errors when the configured .codex source is missing" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-codex-missing-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      missing_codex = Path.join([test_root, "missing", ".codex"])

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        workspace_bootstrap_automation_from: missing_codex
      )

      assert {:error, {:workspace_bootstrap_automation_invalid_source, path, :missing}} =
               Workspace.create_for_issue("S-MISSING")

      assert {:ok, expected_path} = SymphonyElixir.PathSafety.canonicalize(missing_codex)
      assert path == expected_path
    after
      File.rm_rf(test_root)
    end
  end

  test "tapd workspace ignores local workpad files after repository bootstrap" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-tapd-workpad-ignore-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "tapd workspace\n")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "tapd",
        tracker_endpoint: "https://api.tapd.cn",
        tracker_api_token: "tapd-user",
        tracker_api_secret: "tapd-secret",
        tracker_project_slug: nil,
        tracker_assignee: nil,
        tracker_active_states: ["planning"],
        tracker_terminal_states: ["resolved"],
        tracker_platform: %{"workspace_id" => "53070854"},
        workspace_root: workspace_root,
        hook_after_create: """
        git init -b main .
        git remote add origin #{template_repo}
        git fetch --depth 1 origin main
        git reset --hard FETCH_HEAD
        """
      )

      assert {:ok, workspace} = Workspace.create_for_issue("TAPD-WS")

      exclude_path = Path.join([workspace, ".git", "info", "exclude"])
      assert File.read!(exclude_path) =~ ".symphony-tapd-workpad.md"

      File.write!(Path.join(workspace, ".symphony-tapd-workpad.md"), "# tapd workpad\n")

      assert {"!! .symphony-tapd-workpad.md\n", 0} =
               CommandEnv.system_cmd("git", ["status", "--short", "--ignored", ".symphony-tapd-workpad.md"], cd: workspace)

      assert {:ok, ^workspace} = Workspace.create_for_issue("TAPD-WS")

      assert exclude_path
             |> File.read!()
             |> String.split("\n", trim: true)
             |> Enum.count(&(&1 == ".symphony-tapd-workpad.md")) == 1
    after
      File.rm_rf(test_root)
    end
  end

  test "non-tapd workspace does not install tapd workpad ignore entries" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-linear-workpad-ignore-#{System.unique_integer([:positive])}"
      )

    try do
      template_repo = Path.join(test_root, "source")
      workspace_root = Path.join(test_root, "workspaces")

      File.mkdir_p!(template_repo)
      File.write!(Path.join(template_repo, "README.md"), "linear workspace\n")
      CommandEnv.system_cmd("git", ["-C", template_repo, "init", "-b", "main"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "add", "README.md"])
      CommandEnv.system_cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "linear",
        workspace_root: workspace_root,
        hook_after_create: """
        git init -b main .
        git remote add origin #{template_repo}
        git fetch --depth 1 origin main
        git reset --hard FETCH_HEAD
        """
      )

      assert {:ok, workspace} = Workspace.create_for_issue("LIN-WS")

      exclude_path = Path.join([workspace, ".git", "info", "exclude"])
      refute File.read!(exclude_path) =~ ".symphony-tapd-workpad.md"
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace path is deterministic per issue identifier" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-deterministic-#{System.unique_integer([:positive])}"
      )

    write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

    assert {:ok, first_workspace} = Workspace.create_for_issue("MT/Det")
    assert {:ok, second_workspace} = Workspace.create_for_issue("MT/Det")

    assert first_workspace == second_workspace
    assert Path.basename(first_workspace) == "MT_Det"
  end

  test "workspace reuses existing issue directory without deleting local changes" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-reuse-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "echo first > README.md"
      )

      assert {:ok, first_workspace} = Workspace.create_for_issue("MT-REUSE")

      File.write!(Path.join(first_workspace, "README.md"), "changed\n")
      File.write!(Path.join(first_workspace, "local-progress.txt"), "in progress\n")
      File.mkdir_p!(Path.join(first_workspace, "deps"))
      File.mkdir_p!(Path.join(first_workspace, "_build"))
      File.mkdir_p!(Path.join(first_workspace, "tmp"))
      File.write!(Path.join([first_workspace, "deps", "cache.txt"]), "cached deps\n")
      File.write!(Path.join([first_workspace, "_build", "artifact.txt"]), "compiled artifact\n")
      File.write!(Path.join([first_workspace, "tmp", "scratch.txt"]), "remove me\n")

      assert {:ok, second_workspace} = Workspace.create_for_issue("MT-REUSE")
      assert second_workspace == first_workspace
      assert File.read!(Path.join(second_workspace, "README.md")) == "changed\n"
      assert File.read!(Path.join(second_workspace, "local-progress.txt")) == "in progress\n"
      assert File.read!(Path.join([second_workspace, "deps", "cache.txt"])) == "cached deps\n"

      assert File.read!(Path.join([second_workspace, "_build", "artifact.txt"])) ==
               "compiled artifact\n"

      assert File.read!(Path.join([second_workspace, "tmp", "scratch.txt"])) == "remove me\n"
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace replaces stale non-directory paths" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-stale-path-#{System.unique_integer([:positive])}"
      )

    try do
      stale_workspace = Path.join(workspace_root, "MT-STALE")
      File.mkdir_p!(workspace_root)
      File.write!(stale_workspace, "old state\n")

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      assert {:ok, canonical_workspace} = SymphonyElixir.PathSafety.canonicalize(stale_workspace)
      assert {:ok, workspace} = Workspace.create_for_issue("MT-STALE")
      assert workspace == canonical_workspace
      assert File.dir?(workspace)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace rejects symlink escapes under the configured root" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-symlink-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      outside_root = Path.join(test_root, "outside")
      symlink_path = Path.join(workspace_root, "MT-SYM")

      File.mkdir_p!(workspace_root)
      File.mkdir_p!(outside_root)
      File.ln_s!(outside_root, symlink_path)

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      assert {:ok, canonical_outside_root} = SymphonyElixir.PathSafety.canonicalize(outside_root)

      assert {:ok, canonical_workspace_root} =
               SymphonyElixir.PathSafety.canonicalize(workspace_root)

      assert {:error, {:workspace_outside_root, ^canonical_outside_root, ^canonical_workspace_root}} =
               Workspace.create_for_issue("MT-SYM")
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace canonicalizes symlinked workspace roots before creating issue directories" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-root-symlink-#{System.unique_integer([:positive])}"
      )

    try do
      actual_root = Path.join(test_root, "actual-workspaces")
      linked_root = Path.join(test_root, "linked-workspaces")

      File.mkdir_p!(actual_root)
      File.ln_s!(actual_root, linked_root)

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: linked_root)

      assert {:ok, canonical_workspace} =
               SymphonyElixir.PathSafety.canonicalize(Path.join(actual_root, "MT-LINK"))

      assert {:ok, workspace} = Workspace.create_for_issue("MT-LINK")
      assert workspace == canonical_workspace
      assert File.dir?(workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace remove rejects the workspace root itself with a distinct error" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-root-remove-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(workspace_root)
      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      assert {:ok, canonical_workspace_root} =
               SymphonyElixir.PathSafety.canonicalize(workspace_root)

      assert {:error, {:workspace_equals_root, ^canonical_workspace_root, ^canonical_workspace_root}, ""} =
               Workspace.remove(workspace_root)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace surfaces after_create hook failures" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-hook-failure-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "echo nope && exit 17"
      )

      log =
        capture_log(fn ->
          assert {:error, {:workspace_hook_failed, "after_create", 17, _output}} =
                   Workspace.create_for_issue("MT-FAIL")
        end)

      assert log =~ "workspace_prepare_started"
      assert log =~ "workspace_hook_started"
      assert log =~ "workspace_hook_failed"
      assert log =~ "workspace_prepare_failed"
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace surfaces after_create hook timeouts" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-hook-timeout-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_timeout_ms: 10,
        hook_after_create: "sleep 1"
      )

      assert {:error, {:workspace_hook_timeout, "after_create", 10}} =
               Workspace.create_for_issue("MT-TIMEOUT")
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace emits structured lifecycle events for successful prepare" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-lifecycle-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      log =
        capture_log(fn ->
          assert {:ok, _workspace} = Workspace.create_for_issue("MT-LIFECYCLE")
        end)

      assert log =~ "workspace_prepare_started"
      assert log =~ "workspace_automation_bootstrap_started"
      assert log =~ "workspace_automation_bootstrap_succeeded"
      assert log =~ "workspace_prepare_succeeded"
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace creates a directory with bundled automation codex when no bootstrap hook is configured" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-workspace-empty-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      workspace = Path.join(workspace_root, "MT-608")
      assert {:ok, canonical_workspace} = SymphonyElixir.PathSafety.canonicalize(workspace)

      assert {:ok, ^canonical_workspace} = Workspace.create_for_issue("MT-608")
      assert File.dir?(workspace)
      assert {:ok, entries} = File.ls(workspace)
      assert Enum.sort(entries) == [".codex"]
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace removes all workspaces for a closed issue identifier" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-issue-workspace-cleanup-#{System.unique_integer([:positive])}"
      )

    try do
      target_workspace = Path.join(workspace_root, "S_1")

      untouched_workspace =
        Path.join(workspace_root, "OTHER-#{System.unique_integer([:positive])}")

      File.mkdir_p!(target_workspace)
      File.mkdir_p!(untouched_workspace)
      File.write!(Path.join(target_workspace, "marker.txt"), "stale")
      File.write!(Path.join(untouched_workspace, "marker.txt"), "keep")

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      assert :ok = Workspace.remove_issue_workspaces("S_1")
      refute File.exists?(target_workspace)
      assert File.exists?(untouched_workspace)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "workspace cleanup handles missing workspace root" do
    missing_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-missing-workspaces-#{System.unique_integer([:positive])}"
      )

    write_workflow_file!(Workflow.workflow_file_path(), workspace_root: missing_root)

    assert :ok = Workspace.remove_issue_workspaces("S-2")
  end

  test "workspace cleanup ignores non-binary identifier" do
    assert :ok = Workspace.remove_issue_workspaces(nil)
  end

  test "linear issue helpers" do
    issue = %Issue{
      id: "abc",
      labels: ["frontend", "infra"],
      assigned_to_worker: false
    }

    assert Issue.label_names(issue) == ["frontend", "infra"]
    assert issue.labels == ["frontend", "infra"]
    refute issue.assigned_to_worker
  end

  test "linear client normalizes blockers from inverse relations" do
    raw_issue = %{
      "id" => "issue-1",
      "identifier" => "MT-1",
      "title" => "Blocked todo",
      "description" => "Needs dependency",
      "priority" => 2,
      "state" => %{"name" => "Todo"},
      "branchName" => "mt-1",
      "url" => "https://example.org/issues/MT-1",
      "assignee" => %{
        "id" => "user-1"
      },
      "labels" => %{"nodes" => [%{"name" => "Backend"}]},
      "inverseRelations" => %{
        "nodes" => [
          %{
            "type" => "blocks",
            "issue" => %{
              "id" => "issue-2",
              "identifier" => "MT-2",
              "state" => %{"name" => "In Progress"}
            }
          },
          %{
            "type" => "relatesTo",
            "issue" => %{
              "id" => "issue-3",
              "identifier" => "MT-3",
              "state" => %{"name" => "Done"}
            }
          }
        ]
      },
      "createdAt" => "2026-01-01T00:00:00Z",
      "updatedAt" => "2026-01-02T00:00:00Z"
    }

    issue =
      Normalizer.normalize_issue(
        raw_issue,
        %{match_values: MapSet.new(["user-1"])},
        state_phase_map: %{
          "Todo" => "todo",
          "In Progress" => "in_progress",
          "Done" => "done"
        }
      )

    assert issue.blocked_by == [
             %{
               id: "issue-2",
               identifier: "MT-2",
               state: "In Progress",
               lifecycle_phase: "in_progress"
             }
           ]

    assert issue.labels == ["backend"]
    assert issue.priority == 2
    assert issue.state == "Todo"
    assert issue.lifecycle_phase == "todo"
    assert issue.assignee_id == "user-1"
    assert issue.assigned_to_worker
  end

  test "linear client marks explicitly unassigned issues as not routed to worker" do
    raw_issue = %{
      "id" => "issue-99",
      "identifier" => "MT-99",
      "title" => "Someone else's task",
      "state" => %{"name" => "Todo"},
      "assignee" => %{
        "id" => "user-2"
      }
    }

    issue = Normalizer.normalize_issue(raw_issue, %{match_values: MapSet.new(["user-1"])})

    refute issue.assigned_to_worker
  end

  test "linear client pagination merge helper preserves issue ordering" do
    issue_page_1 = [
      %Issue{id: "issue-1", identifier: "MT-1"},
      %Issue{id: "issue-2", identifier: "MT-2"}
    ]

    issue_page_2 = [
      %Issue{id: "issue-3", identifier: "MT-3"}
    ]

    merged =
      [issue_page_1, issue_page_2]
      |> Enum.reduce([], &Pagination.prepend_page_issues/2)
      |> Pagination.finalize_paginated_issues()

    assert Enum.map(merged, & &1.identifier) == ["MT-1", "MT-2", "MT-3"]
  end

  test "linear client paginates issue state fetches by id beyond one page" do
    issue_ids = Enum.map(1..55, &"issue-#{&1}")
    first_batch_ids = Enum.take(issue_ids, 50)
    second_batch_ids = Enum.drop(issue_ids, 50)

    raw_issue = fn issue_id ->
      suffix = String.replace_prefix(issue_id, "issue-", "")

      %{
        "id" => issue_id,
        "identifier" => "MT-#{suffix}",
        "title" => "Issue #{suffix}",
        "description" => "Description #{suffix}",
        "state" => %{"name" => "In Progress"},
        "labels" => %{"nodes" => []},
        "inverseRelations" => %{"nodes" => []}
      }
    end

    graphql_fun = fn query, variables ->
      send(self(), {:fetch_issue_states_page, query, variables})

      body = %{
        "data" => %{
          "issues" => %{
            "nodes" => Enum.map(variables.ids, raw_issue)
          }
        }
      }

      {:ok, body}
    end

    assert {:ok, issues} =
             IssueReader.fetch_issue_states(
               issue_ids,
               nil,
               graphql_fun,
               TrackerConfig.current!() |> TrackerConfig.state_phase_map()
             )

    assert Enum.map(issues, & &1.id) == issue_ids

    assert_receive {:fetch_issue_states_page, query, %{ids: ^first_batch_ids, first: 50, relationFirst: 50}}

    assert query =~ "SymphonyLinearIssuesById"

    assert_receive {:fetch_issue_states_page, ^query, %{ids: ^second_batch_ids, first: 5, relationFirst: 50}}
  end

  test "linear client logs response bodies for non-200 graphql responses" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error,
                %TrackerError{
                  provider: "linear",
                  operation: :request,
                  code: :http_status,
                  details: %{status: 400}
                }} =
                 Client.graphql(
                   "query Viewer { viewer { id } }",
                   %{},
                   tracker: TrackerConfig.current!(),
                   request_fun: fn _payload, _headers ->
                     {:ok,
                      %{
                        status: 400,
                        body: %{
                          "errors" => [
                            %{
                              "message" => "Variable \"$ids\" got invalid value",
                              "extensions" => %{"code" => "BAD_USER_INPUT"}
                            }
                          ]
                        }
                      }}
                   end
                 )
      end)

    assert log =~ "tracker_request_failed"
    assert log =~ "status=400"
    assert log =~ "BAD_USER_INPUT"
    assert log =~ "got invalid value"
  end

  test "orchestrator sorts dispatch by priority then oldest created_at" do
    issue_same_priority_older = %Issue{
      id: "issue-old-high",
      identifier: "MT-200",
      title: "Old high priority",
      state: "Todo",
      priority: 1,
      created_at: ~U[2026-01-01 00:00:00Z]
    }

    issue_same_priority_newer = %Issue{
      id: "issue-new-high",
      identifier: "MT-201",
      title: "New high priority",
      state: "Todo",
      priority: 1,
      created_at: ~U[2026-01-02 00:00:00Z]
    }

    issue_lower_priority_older = %Issue{
      id: "issue-old-low",
      identifier: "MT-199",
      title: "Old lower priority",
      state: "Todo",
      priority: 2,
      created_at: ~U[2025-12-01 00:00:00Z]
    }

    sorted =
      sort_issues_for_dispatch([
        issue_lower_priority_older,
        issue_same_priority_newer,
        issue_same_priority_older
      ])

    assert Enum.map(sorted, & &1.identifier) == ["MT-200", "MT-201", "MT-199"]
  end

  test "todo issue with non-terminal blocker is not dispatch-eligible" do
    state = %Orchestrator.State{
      max_concurrent_agents: 3,
      running: %{},
      claimed: MapSet.new(),
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: "blocked-1",
      identifier: "MT-1001",
      title: "Blocked work",
      state: "Todo",
      blocked_by: [%{id: "blocker-1", identifier: "MT-1002", state: "In Progress"}]
    }

    refute should_dispatch_issue(issue, state)
  end

  test "issue assigned to another worker is not dispatch-eligible" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_assignee: "dev@example.com")

    state = %Orchestrator.State{
      max_concurrent_agents: 3,
      running: %{},
      claimed: MapSet.new(),
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: "assigned-away-1",
      identifier: "MT-1007",
      title: "Owned elsewhere",
      state: "Todo",
      assigned_to_worker: false
    }

    refute should_dispatch_issue(issue, state)
  end

  test "todo issue with terminal blockers remains dispatch-eligible" do
    state = %Orchestrator.State{
      max_concurrent_agents: 3,
      running: %{},
      claimed: MapSet.new(),
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: "ready-1",
      identifier: "MT-1003",
      title: "Ready work",
      state: "Todo",
      blocked_by: [%{id: "blocker-2", identifier: "MT-1004", state: "Closed"}]
    }

    assert should_dispatch_issue(issue, state)
  end

  test "tapd active issue with non-terminal blockers is not dispatch-eligible" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning", "developing"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    state = %Orchestrator.State{
      max_concurrent_agents: 3,
      running: %{},
      claimed: MapSet.new(),
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    issue = %Issue{
      id: "tapd-blocked-1",
      identifier: "TAPD-1001",
      title: "Blocked TAPD work",
      state: "planning",
      blocked_by: [%{id: "tapd-blocker-1", identifier: "TAPD-1002", state: "developing"}]
    }

    refute should_dispatch_issue(issue, state)
  end

  test "tapd workflows_by_type expands tracker state unions during config parsing" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      tracker_state_phase_map: nil,
      tracker_workflows_by_type: %{
        "story" => %{
          "active_states" => ["planning", "developing", "merging", "rework"],
          "terminal_states" => ["resolved", "rejected"],
          "state_phase_map" => %{
            "planning" => "todo",
            "developing" => "in_progress",
            "review" => "human_review",
            "merging" => "merging",
            "rework" => "rework",
            "resolved" => "done",
            "rejected" => "canceled"
          },
          "raw_state_by_route_key" => %{
            "planning" => "planning",
            "developing" => "developing",
            "review" => "review",
            "merging" => "merging",
            "rework" => "rework",
            "resolved" => "resolved",
            "rejected" => "rejected"
          }
        },
        "feature" => %{
          "active_states" => ["queued", "coding", "shipping", "fixback"],
          "terminal_states" => ["done", "canceled"],
          "state_phase_map" => %{
            "queued" => "todo",
            "coding" => "in_progress",
            "qa_review" => "human_review",
            "shipping" => "merging",
            "fixback" => "rework",
            "done" => "done",
            "canceled" => "canceled"
          },
          "raw_state_by_route_key" => %{
            "planning" => "queued",
            "developing" => "coding",
            "review" => "qa_review",
            "merging" => "shipping",
            "rework" => "fixback",
            "resolved" => "done",
            "rejected" => "canceled"
          }
        }
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    settings = Config.settings!()

    assert Enum.sort(TrackerConfig.active_states(settings.tracker)) ==
             [
               "coding",
               "developing",
               "fixback",
               "merging",
               "planning",
               "queued",
               "rework",
               "shipping"
             ]

    assert Enum.sort(TrackerConfig.terminal_states(settings.tracker)) == [
             "canceled",
             "done",
             "rejected",
             "resolved"
           ]
  end

  test "linear workflow config exposes effective coding profile routes on issues" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "PROJ"
    )

    workflow = Config.settings!().tracker |> LinearWorkflowConfig.global_workflow()

    assert workflow.profile.kind == "coding_pr_delivery"
    assert workflow.raw_state_by_route_key.planning == "Todo"
    assert workflow.raw_state_by_route_key.developing == "In Progress"
    assert workflow.raw_state_by_route_key.review == "In Review"

    assert workflow.policy_by_route_key.planning == %{
             action: :transition_then_dispatch,
             transition_target: :developing
           }

    issue =
      Normalizer.normalize_issue(
        %{
          "id" => "issue-1",
          "identifier" => "MT-1",
          "title" => "Linear workflow route",
          "state" => %{"name" => "In Progress"},
          "labels" => %{"nodes" => []},
          "inverseRelations" => %{"nodes" => []}
        },
        nil,
        state_phase_map: workflow.state_phase_map,
        workflow: workflow
      )

    assert issue.workflow == workflow
    assert IssueContext.route_facts(issue).route_key == :developing
    assert IssueContext.route_facts(issue).action == :dispatch
  end

  test "linear config validation rejects route keys outside the active profile vocabulary" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "PROJ",
      tracker_raw_state_by_route_key: %{
        "planning" => "Todo",
        "developing" => "In Progress",
        "review" => "In Review",
        "merging" => "Merging",
        "rework" => "Rework",
        "resolved" => "Done",
        "rejected" => "Canceled",
        "qa_review" => "In Review"
      }
    )

    assert {:error,
            %TrackerError{
              provider: "linear",
              operation: :validate_config,
              details: %{
                source_reason: {:invalid_linear_workflow_config, {:invalid_raw_state_route_key, :global, "qa_review"}}
              }
            }} = LinearAdapter.validate_config(Config.settings!().tracker)
  end

  test "linear config validation rejects route policy keys outside the active profile vocabulary" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "PROJ",
      tracker_policy_by_route_key: %{
        "qa_review" => %{"action" => "wait"}
      }
    )

    assert {:error,
            %TrackerError{
              provider: "linear",
              operation: :validate_config,
              details: %{
                source_reason: {:invalid_linear_workflow_config, {:invalid_route_policy_key, :global, "qa_review"}}
              }
            }} = LinearAdapter.validate_config(Config.settings!().tracker)
  end

  test "tapd global raw_state_by_route_key config is preserved and exposed through the global workflow" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["status_4", "developing", "merging", "rework"],
      tracker_terminal_states: ["resolved", "rejected"],
      tracker_state_phase_map: %{
        "status_4" => "todo",
        "developing" => "in_progress",
        "status_5" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      tracker_raw_state_by_route_key: %{
        "planning" => "status_4",
        "developing" => "developing",
        "review" => "status_5",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "resolved",
        "rejected" => "rejected"
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    settings = Config.settings!()
    workflow = SymphonyElixir.Tracker.Tapd.WorkflowConfig.global_workflow(settings.tracker)

    assert %SymphonyElixir.Workflow.Effective{} = workflow

    assert TrackerConfig.lifecycle(settings.tracker)["raw_state_by_route_key"] == %{
             "planning" => "status_4",
             "developing" => "developing",
             "review" => "status_5",
             "merging" => "merging",
             "rework" => "rework",
             "resolved" => "resolved",
             "rejected" => "rejected"
           }

    assert workflow.raw_state_by_route_key == %{
             planning: "status_4",
             developing: "developing",
             review: "status_5",
             merging: "merging",
             rework: "rework",
             resolved: "resolved",
             rejected: "rejected"
           }

    assert workflow.policy_by_route_key == %{
             planning: %{action: :transition_then_dispatch, transition_target: :developing},
             developing: %{action: :dispatch},
             review: %{action: :wait},
             merging: %{action: :dispatch, execution_profile: "land"},
             rework: %{action: :dispatch},
             resolved: %{action: :stop},
             rejected: %{action: :stop}
           }

    assert workflow.completion_contract.allowed_completion_routes == [
             "review",
             "merging",
             "rework",
             "resolved",
             "rejected"
           ]
  end

  test "tapd global policy_by_route_key config is preserved and exposed through the global workflow" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["status_4", "developing", "merging", "rework"],
      tracker_terminal_states: ["resolved", "rejected"],
      tracker_state_phase_map: %{
        "status_4" => "todo",
        "developing" => "in_progress",
        "status_5" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      tracker_raw_state_by_route_key: %{
        "planning" => "status_4",
        "developing" => "developing",
        "review" => "status_5",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "resolved",
        "rejected" => "rejected"
      },
      tracker_policy_by_route_key: %{
        "planning" => %{"action" => "transition_then_dispatch", "transition_target" => "developing"},
        "developing" => %{"action" => "dispatch"},
        "review" => %{"action" => "wait"},
        "merging" => %{"action" => "dispatch", "execution_profile" => "land"},
        "rework" => %{"action" => "dispatch"},
        "resolved" => %{"action" => "stop"},
        "rejected" => %{"action" => "stop"}
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    settings = Config.settings!()
    workflow = SymphonyElixir.Tracker.Tapd.WorkflowConfig.global_workflow(settings.tracker)

    assert TrackerConfig.lifecycle(settings.tracker)["policy_by_route_key"] == %{
             "planning" => %{
               "action" => "transition_then_dispatch",
               "transition_target" => "developing"
             },
             "developing" => %{"action" => "dispatch"},
             "review" => %{"action" => "wait"},
             "merging" => %{"action" => "dispatch", "execution_profile" => "land"},
             "rework" => %{"action" => "dispatch"},
             "resolved" => %{"action" => "stop"},
             "rejected" => %{"action" => "stop"}
           }

    assert workflow.policy_by_route_key == %{
             planning: %{action: :transition_then_dispatch, transition_target: :developing},
             developing: %{action: :dispatch},
             review: %{action: :wait},
             merging: %{action: :dispatch, execution_profile: "land"},
             rework: %{action: :dispatch},
             resolved: %{action: :stop},
             rejected: %{action: :stop}
           }
  end

  test "tapd dispatch uses issue-specific workflows when global state unions overlap" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      tracker_state_phase_map: nil,
      tracker_workflows_by_type: %{
        "story" => %{
          "active_states" => ["planning", "developing", "merging", "rework"],
          "terminal_states" => ["resolved", "rejected"],
          "state_phase_map" => %{
            "planning" => "todo",
            "developing" => "in_progress",
            "review" => "human_review",
            "merging" => "merging",
            "rework" => "rework",
            "resolved" => "done",
            "rejected" => "canceled"
          },
          "raw_state_by_route_key" => %{
            "planning" => "planning",
            "developing" => "developing",
            "review" => "review",
            "merging" => "merging",
            "rework" => "rework",
            "resolved" => "resolved",
            "rejected" => "rejected"
          }
        },
        "feature" => %{
          "active_states" => ["queued", "coding", "shipping", "fixback"],
          "terminal_states" => ["done", "canceled"],
          "state_phase_map" => %{
            "queued" => "todo",
            "coding" => "in_progress",
            "qa_review" => "human_review",
            "shipping" => "merging",
            "fixback" => "rework",
            "done" => "done",
            "canceled" => "canceled"
          },
          "raw_state_by_route_key" => %{
            "planning" => "queued",
            "developing" => "coding",
            "review" => "qa_review",
            "merging" => "shipping",
            "rework" => "fixback",
            "resolved" => "done",
            "rejected" => "canceled"
          }
        }
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    state = %Orchestrator.State{
      max_concurrent_agents: 3,
      running: %{},
      claimed: MapSet.new(),
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }

    story_issue = %Issue{
      id: "tapd-story-1",
      identifier: "TAPD-2001",
      title: "Story issue should not borrow feature active states",
      state: "coding",
      workitem_type_id: "story",
      workflow: %{
        active_states: ["planning", "developing", "merging", "rework"],
        terminal_states: ["resolved", "rejected"],
        state_phase_map: %{
          "planning" => "todo",
          "developing" => "in_progress",
          "review" => "human_review",
          "merging" => "merging",
          "rework" => "rework",
          "resolved" => "done",
          "rejected" => "canceled"
        },
        raw_state_by_route_key: %{developing: "developing"}
      }
    }

    feature_issue = %Issue{
      id: "tapd-feature-1",
      identifier: "TAPD-2002",
      title: "Feature issue should use its own active states",
      state: "coding",
      workitem_type_id: "feature",
      workflow: %{
        active_states: ["queued", "coding", "shipping", "fixback"],
        terminal_states: ["done", "canceled"],
        state_phase_map: %{
          "queued" => "todo",
          "coding" => "in_progress",
          "qa_review" => "human_review",
          "shipping" => "merging",
          "fixback" => "rework",
          "done" => "done",
          "canceled" => "canceled"
        },
        raw_state_by_route_key: %{developing: "coding"}
      }
    }

    refute should_dispatch_issue(story_issue, state)
    assert should_dispatch_issue(feature_issue, state)
  end

  test "tapd dispatch preparation transitions planning route to developing before dispatch" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["status_4", "developing", "merging", "rework"],
      tracker_terminal_states: ["resolved", "rejected"],
      tracker_state_phase_map: %{
        "status_4" => "todo",
        "developing" => "in_progress",
        "status_5" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      tracker_raw_state_by_route_key: %{
        "planning" => "status_4",
        "developing" => "developing",
        "review" => "status_5",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "resolved",
        "rejected" => "rejected"
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    workflow = %{
      active_states: ["status_4", "developing", "merging", "rework"],
      terminal_states: ["resolved", "rejected"],
      state_phase_map: %{
        "status_4" => "todo",
        "developing" => "in_progress",
        "status_5" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      raw_state_by_route_key: %{
        planning: "status_4",
        developing: "developing",
        review: "status_5",
        merging: "merging",
        rework: "rework",
        resolved: "resolved",
        rejected: "rejected"
      }
    }

    issue = %Issue{
      id: "tapd-route-1",
      identifier: "TAPD-3001",
      title: "Route policy dispatch prep",
      state: "status_4",
      workflow: workflow
    }

    refreshed_issue = %Issue{issue | state: "developing"}

    fetcher = fn ["tapd-route-1"] -> {:ok, [refreshed_issue]} end

    state_updater = fn "tapd-route-1", "developing" ->
      send(self(), {:tapd_state_update, "tapd-route-1", "developing"})
      :ok
    end

    assert {:ok, %Issue{state: "developing"} = prepared_issue} =
             prepare_issue_for_dispatch(issue, fetcher, state_updater)

    assert prepared_issue.identifier == "TAPD-3001"
    assert_receive {:tapd_state_update, "tapd-route-1", "developing"}
  end

  test "dispatch revalidation skips stale todo issue once a non-terminal blocker appears" do
    stale_issue = %Issue{
      id: "blocked-2",
      identifier: "MT-1005",
      title: "Stale blocked work",
      state: "Todo",
      blocked_by: []
    }

    refreshed_issue = %Issue{
      id: "blocked-2",
      identifier: "MT-1005",
      title: "Stale blocked work",
      state: "Todo",
      blocked_by: [%{id: "blocker-3", identifier: "MT-1006", state: "In Progress"}]
    }

    fetcher = fn ["blocked-2"] -> {:ok, [refreshed_issue]} end

    assert {:skip, %Issue{} = skipped_issue} =
             revalidate_issue_for_dispatch(stale_issue, fetcher)

    assert skipped_issue.identifier == "MT-1005"

    assert skipped_issue.blocked_by == [
             %{id: "blocker-3", identifier: "MT-1006", state: "In Progress"}
           ]
  end

  test "dispatch revalidation skips stale TAPD active issue once a non-terminal blocker appears" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning", "developing"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    stale_issue = %Issue{
      id: "tapd-blocked-2",
      identifier: "TAPD-1003",
      title: "Stale blocked TAPD work",
      state: "planning",
      blocked_by: []
    }

    refreshed_issue = %Issue{
      id: "tapd-blocked-2",
      identifier: "TAPD-1003",
      title: "Stale blocked TAPD work",
      state: "planning",
      blocked_by: [%{id: "tapd-blocker-2", identifier: "TAPD-1004", state: "developing"}]
    }

    fetcher = fn ["tapd-blocked-2"] -> {:ok, [refreshed_issue]} end

    assert {:skip, %Issue{} = skipped_issue} =
             revalidate_issue_for_dispatch(stale_issue, fetcher)

    assert skipped_issue.identifier == "TAPD-1003"

    assert skipped_issue.blocked_by == [
             %{id: "tapd-blocker-2", identifier: "TAPD-1004", state: "developing"}
           ]
  end

  test "workspace remove returns error information for missing directory" do
    random_path =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-missing-#{System.unique_integer([:positive])}"
      )

    assert {:ok, []} = Workspace.remove(random_path)
  end

  test "workspace hooks support multiline YAML scripts and run at lifecycle boundaries" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-hooks-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      before_remove_marker = Path.join(test_root, "before_remove.log")
      after_create_counter = Path.join(test_root, "after_create.count")

      File.mkdir_p!(workspace_root)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "echo after_create > after_create.log\necho call >> \"#{after_create_counter}\"",
        hook_before_remove: "echo before_remove > \"#{before_remove_marker}\""
      )

      config = Config.settings!()
      assert config.hooks.after_create =~ "echo after_create > after_create.log"
      assert config.hooks.before_remove =~ "echo before_remove >"

      assert {:ok, workspace} = Workspace.create_for_issue("MT-HOOKS")
      assert File.read!(Path.join(workspace, "after_create.log")) == "after_create\n"

      assert {:ok, _workspace} = Workspace.create_for_issue("MT-HOOKS")
      assert length(String.split(String.trim(File.read!(after_create_counter)), "\n")) == 1

      assert :ok = Workspace.remove_issue_workspaces("MT-HOOKS")
      assert File.read!(before_remove_marker) == "before_remove\n"
      refute File.exists?(workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace remove continues when before_remove hook fails" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-hooks-fail-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")

      File.mkdir_p!(workspace_root)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_before_remove: "echo failure && exit 17"
      )

      assert {:ok, workspace} = Workspace.create_for_issue("MT-HOOKS-FAIL")
      assert :ok = Workspace.remove_issue_workspaces("MT-HOOKS-FAIL")
      refute File.exists?(workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace remove continues when before_remove hook fails with large output" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-hooks-large-fail-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")

      File.mkdir_p!(workspace_root)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_before_remove: "i=0; while [ $i -lt 3000 ]; do printf a; i=$((i+1)); done; exit 17"
      )

      assert {:ok, workspace} = Workspace.create_for_issue("MT-HOOKS-LARGE-FAIL")
      assert :ok = Workspace.remove_issue_workspaces("MT-HOOKS-LARGE-FAIL")
      refute File.exists?(workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "workspace remove continues when before_remove hook times out" do
    previous_timeout = Application.get_env(:symphony_elixir, :workspace_hook_timeout_ms)

    on_exit(fn ->
      if is_nil(previous_timeout) do
        Application.delete_env(:symphony_elixir, :workspace_hook_timeout_ms)
      else
        Application.put_env(:symphony_elixir, :workspace_hook_timeout_ms, previous_timeout)
      end
    end)

    Application.put_env(:symphony_elixir, :workspace_hook_timeout_ms, 10)

    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-hooks-timeout-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")

      File.mkdir_p!(workspace_root)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_before_remove: "sleep 1"
      )

      assert {:ok, workspace} = Workspace.create_for_issue("MT-HOOKS-TIMEOUT")
      assert :ok = Workspace.remove_issue_workspaces("MT-HOOKS-TIMEOUT")
      refute File.exists?(workspace)
    after
      File.rm_rf(test_root)
    end
  end

  test "config validates explicit workflow profile selection" do
    write_workflow_file!(Workflow.workflow_file_path(),
      workflow_profile_kind: "triage",
      workflow_profile_options: %{"routing_taxonomy" => ["bug", "feature"]}
    )

    config = Config.settings!()

    assert config.workflow.profile == %{
             "kind" => "triage",
             "version" => 1,
             "options" => %{"routing_taxonomy" => ["bug", "feature"], "allow_duplicate_route" => true}
           }

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), workflow_profile_kind: "missing")
    assert {:error, {:unsupported_workflow_profile, "missing", 1}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      workflow_profile_kind: "triage",
      workflow_profile_options: %{"unknown" => true}
    )

    assert {:error, {:unknown_profile_option, "triage", "unknown"}} = Config.validate!()
  end

  test "config validates workflow profile required capabilities" do
    Application.put_env(:symphony_elixir, :repo_provider_adapters, %{
      "limited" => LimitedRepoProviderAdapter
    })

    on_exit(fn -> Application.delete_env(:symphony_elixir, :repo_provider_adapters) end)

    write_workflow_file!(Workflow.workflow_file_path(), repo_provider_kind: "limited")

    assert {:error, {:missing_workflow_capability, "coding_pr_delivery", 1, "repo_provider.change_proposal.create", :repo_provider}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "limited",
      workflow_profile_options: %{"requirements" => %{"change_proposal" => false}}
    )

    assert {:error, {:missing_workflow_capability, "coding_pr_delivery", 1, "repo_provider.merge", :repo_provider}} =
             Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "limited",
      workflow_profile_options: %{"requirements" => %{"change_proposal" => false}},
      tracker_policy_by_route_key: %{
        "merging" => %{"action" => "wait"}
      }
    )

    assert :ok = Config.validate!()
  end

  test "config validates required typed workflow tools against captured dynamic tools" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{
      "missing_typed_tool_tracker" => MissingTypedToolTrackerAdapter
    })

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
      Application.delete_env(:symphony_elixir, :typed_workflow_tool_fallback_policy)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "missing_typed_tool_tracker",
      tracker_api_token: nil,
      tracker_project_slug: nil,
      workflow_profile_options: %{
        "requirements" => %{
          "change_proposal" => false,
          "typed_tracker_tools" => true
        }
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"action" => "wait"}
      }
    )

    assert {:error, {:typed_workflow_tool_resolution_failed, "coding_pr_delivery", 1, "tracker.issue_snapshot", :missing}} = Config.validate!()
  end

  test "config requires explicit policy before raw tools can satisfy typed workflow capabilities" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{
      "raw_fallback_tool_tracker" => RawFallbackToolTrackerAdapter
    })

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
      Application.delete_env(:symphony_elixir, :typed_workflow_tool_fallback_policy)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "raw_fallback_tool_tracker",
      tracker_api_token: nil,
      tracker_project_slug: nil,
      workflow_profile_options: %{
        "requirements" => %{
          "change_proposal" => false,
          "typed_tracker_tools" => true
        }
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"action" => "wait"}
      }
    )

    assert {:error, {:typed_workflow_tool_resolution_failed, "coding_pr_delivery", 1, "tracker.issue_snapshot", :missing}} =
             Config.validate!()

    Application.put_env(:symphony_elixir, :typed_workflow_tool_fallback_policy, %{
      "tracker.issue_snapshot" => %{"tool" => "legacy_tracker_api", "reason" => "temporary migration"},
      "tracker.move_issue" => %{"tool" => "legacy_tracker_api", "reason" => "temporary migration"},
      "tracker.upsert_workpad" => %{"tool" => "legacy_tracker_api", "reason" => "temporary migration"}
    })

    assert :ok = Config.validate!()
  end

  test "config validates required typed repo workflow tools against captured dynamic tools" do
    Application.put_env(:symphony_elixir, :dynamic_tool_sources, [
      SymphonyElixir.Tracker.DynamicToolSource,
      SymphonyElixir.Repo.DynamicToolSource
    ])

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :dynamic_tool_sources)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "github",
      workflow_profile_options: %{
        "requirements" => %{
          "change_proposal" => true,
          "typed_repo_tools" => true
        }
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"action" => "wait"}
      }
    )

    assert {:error, {:typed_workflow_tool_resolution_failed, "coding_pr_delivery", 1, "repo.change_proposal_snapshot", :missing}} = Config.validate!()
  end

  test "config rejects boot-registered execution profiles not declared by the active workflow profile" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        "name" => "ship_without_merge",
        "profile_kind" => "coding_pr_delivery",
        "profile_versions" => [1],
        "supported_actions" => ["dispatch"],
        "required_capabilities" => [],
        "runtime_handler" => ShipWithoutMergeExecutionProfile
      }
    ])

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_policy_by_route_key: %{
        "merging" => %{"execution_profile" => "ship_without_merge"}
      }
    )

    assert {:error,
            {:invalid_selected_workflow_execution_profile, %{action: :dispatch, execution_profile: "ship_without_merge", route_key: :merging},
             {:undeclared_workflow_execution_profile, "ship_without_merge", ["land"]}}} = Config.validate!()
  end

  test "config admits boot-registered execution profiles declared by the active workflow profile" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        "name" => "ship_without_merge",
        "profile_kind" => "coding_pr_delivery",
        "profile_versions" => [1],
        "supported_actions" => ["dispatch"],
        "required_capabilities" => [],
        "runtime_handler" => ShipWithoutMergeExecutionProfile
      }
    ])

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workflow_profile_options: %{
        "execution_profiles" => %{"allowed" => ["ship_without_merge"]}
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"execution_profile" => "ship_without_merge"}
      }
    )

    assert :ok = Config.validate!()

    resolved_profile = SymphonyElixir.Workflow.ProfileRegistry.resolve!(Config.settings!().workflow.profile)

    assert ["ship_without_merge"] ==
             SymphonyElixir.Workflow.ExecutionProfileRegistry.effective_allowed_execution_profiles(resolved_profile)
  end

  test "config rejects declared execution profiles without profile-owned implementation or registry entry" do
    Application.delete_env(:symphony_elixir, :workflow_execution_profiles)
    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workflow_profile_options: %{
        "execution_profiles" => %{"allowed" => ["ship_without_merge"]}
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"execution_profile" => "ship_without_merge"}
      }
    )

    assert {:error,
            {:invalid_selected_workflow_execution_profile, %{action: :dispatch, execution_profile: "ship_without_merge", route_key: :merging},
             {:missing_workflow_execution_profile_registry_entry, "ship_without_merge", "coding_pr_delivery", 1}}} = Config.validate!()
  end

  test "config admits a single keyword execution profile registry entry" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles,
      name: "ship_without_merge",
      profile_kind: "coding_pr_delivery",
      profile_versions: [1],
      supported_actions: [:dispatch],
      required_capabilities: [],
      runtime_handler: ShipWithoutMergeExecutionProfile
    )

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workflow_profile_options: %{
        "execution_profiles" => %{"allowed" => ["ship_without_merge"]}
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"execution_profile" => "ship_without_merge"}
      }
    )

    assert :ok = Config.validate!()
  end

  test "execution profile registry rejects malformed list entries with structured errors" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [[:not_a_pair]])
    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    assert {:error, {:invalid_workflow_execution_profile_registry, {:invalid_registry_entry, [:not_a_pair]}}} =
             SymphonyElixir.Workflow.ExecutionProfileRegistry.validate_registry()
  end

  test "execution profile registry rejects singular profile_version field" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        name: "ship_without_merge",
        profile_kind: "coding_pr_delivery",
        profile_version: 1,
        supported_actions: ["dispatch"],
        required_capabilities: [],
        runtime_handler: ShipWithoutMergeExecutionProfile
      }
    ])

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    assert {:error,
            {:invalid_workflow_execution_profile_registry,
             {:invalid_registry_entry_profile_versions,
              %{
                name: "ship_without_merge",
                profile_kind: "coding_pr_delivery",
                profile_version: 1,
                supported_actions: ["dispatch"],
                required_capabilities: [],
                runtime_handler: ShipWithoutMergeExecutionProfile
              }}}} = SymphonyElixir.Workflow.ExecutionProfileRegistry.validate_registry()
  end

  test "execution profile registry rejects handlers that do not implement the behaviour callbacks" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        name: "missing_required_capabilities",
        profile_kind: "coding_pr_delivery",
        profile_versions: [1],
        supported_actions: ["dispatch"],
        required_capabilities: [],
        runtime_handler: MissingRequiredCapabilitiesExecutionProfile
      }
    ])

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    assert {:error, {:invalid_workflow_execution_profile_registry, {:invalid_registry_entry_runtime_handler_contract, MissingRequiredCapabilitiesExecutionProfile, {:required_capabilities, 0}}}} =
             SymphonyElixir.Workflow.ExecutionProfileRegistry.validate_registry()
  end

  test "execution profile registry rejects handlers that only match callbacks by duck typing" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        name: "duck_typed",
        profile_kind: "coding_pr_delivery",
        profile_versions: [1],
        supported_actions: ["dispatch"],
        required_capabilities: [],
        runtime_handler: DuckTypedExecutionProfile
      }
    ])

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    assert {:error, {:invalid_workflow_execution_profile_registry, {:invalid_registry_entry_runtime_handler_behaviour, DuckTypedExecutionProfile, SymphonyElixir.Workflow.ExecutionProfile}}} =
             SymphonyElixir.Workflow.ExecutionProfileRegistry.validate_registry()
  end

  test "config rejects selected execution profiles outside registry action scope" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        name: "ship_without_merge",
        profile_kind: "coding_pr_delivery",
        profile_versions: [1],
        supported_actions: ["wait"],
        required_capabilities: [],
        runtime_handler: WaitOnlyExecutionProfile
      }
    ])

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workflow_profile_options: %{
        "execution_profiles" => %{"allowed" => ["ship_without_merge"]}
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"execution_profile" => "ship_without_merge"}
      }
    )

    assert {:error,
            {:invalid_selected_workflow_execution_profile, %{action: :dispatch, execution_profile: "ship_without_merge", route_key: :merging},
             {:unsupported_workflow_execution_profile_action, "ship_without_merge", :dispatch}}} = Config.validate!()
  end

  test "config rejects execution profiles on non-dispatch route actions" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_policy_by_route_key: %{
        "merging" => %{"action" => "wait", "execution_profile" => "land"}
      }
    )

    assert {:error, {:invalid_workflow_execution_profile_usage, :global, :merging, :unsupported_action, :wait}} =
             Config.validate!()
  end

  test "config validates runtime execution profile required capabilities" do
    Application.put_env(:symphony_elixir, :repo_provider_adapters, %{
      "limited" => LimitedRepoProviderAdapter
    })

    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        name: "ship_with_merge",
        profile_kind: "coding_pr_delivery",
        profile_versions: [1],
        supported_actions: ["dispatch"],
        required_capabilities: [],
        runtime_handler: ShipWithMergeExecutionProfile
      }
    ])

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :repo_provider_adapters)
      Application.delete_env(:symphony_elixir, :workflow_execution_profiles)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_provider_kind: "limited",
      workflow_profile_options: %{
        "requirements" => %{"change_proposal" => false},
        "execution_profiles" => %{"allowed" => ["ship_with_merge"]}
      },
      tracker_policy_by_route_key: %{
        "merging" => %{"execution_profile" => "ship_with_merge"}
      }
    )

    assert {:error, {:missing_workflow_capability, "coding_pr_delivery", 1, "repo_provider.merge", :repo_provider}} =
             Config.validate!()
  end

  test "config rejects runtime execution profiles not declared by profiles without execution profiles" do
    Application.put_env(:symphony_elixir, :workflow_execution_profiles, [
      %{
        name: "triage_dispatch",
        profile_kind: "triage",
        profile_versions: [1],
        supported_actions: ["dispatch"],
        required_capabilities: [],
        runtime_handler: TriageDispatchExecutionProfile
      }
    ])

    on_exit(fn -> Application.delete_env(:symphony_elixir, :workflow_execution_profiles) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workflow_profile_kind: "triage",
      tracker_policy_by_route_key: %{
        "classifying" => %{"execution_profile" => "triage_dispatch"}
      }
    )

    assert {:error,
            {:invalid_selected_workflow_execution_profile, %{action: :dispatch, execution_profile: "triage_dispatch", route_key: :classifying},
             {:undeclared_workflow_execution_profile, "triage_dispatch", []}}} = Config.validate!()
  end

  test "config reads defaults for optional settings" do
    previous_linear_api_key = System.get_env("LINEAR_API_KEY")
    on_exit(fn -> restore_env("LINEAR_API_KEY", previous_linear_api_key) end)
    System.delete_env("LINEAR_API_KEY")

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: nil,
      max_concurrent_agents: nil,
      agent_provider_options: %{},
      tracker_api_token: nil,
      tracker_project_slug: nil
    )

    config = Config.settings!()
    assert config.tracker.endpoint == "https://api.linear.app/graphql"
    assert TrackerConfig.api_key(config.tracker) == nil
    assert TrackerConfig.provider(config.tracker)["project_slug"] == nil
    assert config.workspace.root == Path.join(System.tmp_dir!(), "symphony_workspaces")
    assert config.worker.max_concurrent_local_agents == nil
    assert config.worker.max_concurrent_agents_per_host == nil
    assert config.agent.execution.max_concurrent_agents == 10

    assert config.workflow.profile == %{
             "kind" => "coding_pr_delivery",
             "version" => 1,
             "options" => %{
               "requirements" => %{
                 "change_proposal" => true,
                 "typed_tracker_tools" => false,
                 "typed_repo_tools" => false
               },
               "execution_profiles" => %{
                 "allowed" => ["land"]
               }
             }
           }

    assert TrackerConfig.lifecycle(config.tracker)["workflow_profile"] == config.workflow.profile
    assert config.agent_provider.kind == "codex"
    assert config.agent_provider.options["command"] == "codex app-server"
    assert config.agent_provider.options["command"] == "codex app-server"
    assert config.agent_provider.options["command_argv"] == nil

    assert config.agent_provider.options["approval_policy"] == "on-request"

    assert config.agent_provider.options["thread_sandbox"] == "workspace-write"

    assert {:ok, canonical_default_workspace_root} =
             SymphonyElixir.PathSafety.canonicalize(Path.join(System.tmp_dir!(), "symphony_workspaces"))

    assert {:ok, runtime_settings} = CodexSettings.runtime_settings()

    assert runtime_settings.turn_sandbox_policy == %{
             "type" => "workspaceWrite",
             "writableRoots" => [canonical_default_workspace_root],
             "readOnlyAccess" => %{"type" => "fullAccess"},
             "networkAccess" => false,
             "excludeTmpdirEnvVar" => false,
             "excludeSlashTmp" => false
           }

    assert config.agent_provider.options["turn_timeout_ms"] == 3_600_000
    assert config.agent_provider.options["read_timeout_ms"] == 5_000
    assert config.agent_provider.options["stall_timeout_ms"] == 300_000
    assert Config.agent_provider_kind() == "codex"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{command: "codex app-server --model gpt-5.3-codex"}
    )

    assert Config.settings!().agent_provider.options["command"] == "codex app-server --model gpt-5.3-codex"

    explicit_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-explicit-sandbox-root-#{System.unique_integer([:positive])}"
      )

    explicit_workspace = Path.join(explicit_root, "MT-EXPLICIT")
    explicit_cache = Path.join(explicit_workspace, "cache")
    File.mkdir_p!(explicit_cache)

    on_exit(fn -> File.rm_rf(explicit_root) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: explicit_root,
      agent_provider_options: %{
        approval_policy: "on-request",
        thread_sandbox: "workspace-write",
        turn_sandbox_policy: %{
          type: "workspaceWrite",
          writableRoots: [explicit_workspace, explicit_cache]
        }
      }
    )

    config = Config.settings!()
    assert config.agent_provider.options["approval_policy"] == "on-request"
    assert config.agent_provider.options["thread_sandbox"] == "workspace-write"

    assert {:ok, runtime_settings} = CodexSettings.runtime_settings(explicit_workspace)

    assert runtime_settings.turn_sandbox_policy == %{
             "type" => "workspaceWrite",
             "writableRoots" => [explicit_workspace, explicit_cache]
           }

    write_workflow_file!(Workflow.workflow_file_path(), tracker_active_states: ",")
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "tracker.lifecycle.active_states"

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_state_phase_map: nil,
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert {:error, :missing_tracker_state_phase_map} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_state_phase_map: %{"planning" => "human_review", "resolved" => "done"},
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert {:error, {:invalid_tracker_state_phase_map, {:invalid_active_phase, "planning", "human_review"}}} =
             Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), max_concurrent_agents: "bad")
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent.execution.max_concurrent_agents"

    File.write!(
      Workflow.workflow_file_path(),
      """
      ---
      agent:
        max_turns: 5
      ---
      Prompt
      """
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "unsupported keys: max_turns"

    File.write!(
      Workflow.workflow_file_path(),
      """
      ---
      agent_policy:
        max_turns: 5
      ---
      Prompt
      """
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_policy must be configured as agent.execution"

    File.write!(
      Workflow.workflow_file_path(),
      """
      ---
      agent_credentials:
        enabled: true
      agent_quota:
        preflight: off
      ---
      Prompt
      """
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_credentials must be configured as agent.credentials"
    assert message =~ "agent_quota must be configured as agent.quota"

    write_workflow_file!(Workflow.workflow_file_path(), worker_max_concurrent_agents_per_host: 0)
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "worker.max_concurrent_agents_per_host"

    write_workflow_file!(Workflow.workflow_file_path(), worker_max_concurrent_local_agents: 0)
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "worker.max_concurrent_local_agents"

    File.write!(
      Workflow.workflow_file_path(),
      """
      ---
      tracker:
        kind: "linear"
        endpoint: "https://api.linear.app/graphql"
        auth: {"api_key": "token", "api_secret": null}
        provider: {"project_slug": "project", "assignee": null, "platform": {}}
        lifecycle:
          active_states: ["Todo", "In Progress"]
          terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
          state_phase_map: {"Backlog": "backlog", "Todo": "todo", "In Progress": "in_progress", "In Review": "human_review", "Merging": "merging", "Rework": "rework", "Done": "done", "Closed": "canceled", "Cancelled": "canceled", "Canceled": "canceled", "Duplicate": "canceled"}
          raw_state_by_route_key: null
          policy_by_route_key: null
          workflows_by_type: null
      polling:
        interval_ms: 30000
      workspace:
        root: "#{Path.join(System.tmp_dir!(), "symphony_workspaces")}"
        bootstrap_automation_from: null
      worker:
        ssh_hosts: []
      repo:
        base_branch: "main"
        provider:
          kind: "github"
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
    assert message =~ "worker.ssh_hosts"

    write_workflow_file!(Workflow.workflow_file_path(), worker_ssh_hosts: ["worker-a", "worker-a"])
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "worker.ssh_hosts"
    assert message =~ "duplicate entry"

    write_workflow_file!(Workflow.workflow_file_path(), worker_ssh_hosts: ["worker-a", "   "])
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "worker.ssh_hosts"
    assert message =~ "blank entry"

    write_workflow_file!(Workflow.workflow_file_path(), worker_ssh_hosts: ["ssh://worker-a"])
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "worker.ssh_hosts"
    assert message =~ "invalid entry"

    write_workflow_file!(Workflow.workflow_file_path(), worker_max_concurrent_agents_per_host: 2, worker_ssh_hosts: nil)
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "worker.max_concurrent_agents_per_host"
    assert message =~ "worker.ssh_hosts"

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{turn_timeout_ms: "bad"})
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "turn_timeout_ms"

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{read_timeout_ms: "bad"})
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "read_timeout_ms"

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{stall_timeout_ms: "bad"})
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "stall_timeout_ms"

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_active_states: %{todo: true},
      tracker_terminal_states: %{done: true},
      poll_interval_ms: %{bad: true},
      workspace_root: 123,
      max_retry_backoff_ms: 0,
      max_concurrent_agents_by_state: %{"Todo" => "1", "Review" => 0, "Done" => "bad"},
      hook_timeout_ms: 0,
      observability_enabled: "maybe",
      observability_refresh_ms: %{bad: true},
      observability_render_interval_ms: %{bad: true},
      observability_file_enabled: "maybe",
      observability_console_enabled: "maybe",
      observability_log_format: "invalid",
      observability_summary_max_bytes: 0,
      observability_global_event_limit: 0,
      observability_issue_event_limit: 0,
      observability_run_event_limit: 0,
      observability_session_event_limit: 0,
      observability_index_key_limit: 0,
      observability_pending_event_queue_limit: 0,
      server_port: -1,
      server_host: 123
    )

    assert {:error, {:invalid_workflow_config, _message}} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{approval_policy: ""})
    assert :ok = Config.validate!()
    assert CodexSettings.current!().approval_policy == ""

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{thread_sandbox: ""})
    assert :ok = Config.validate!()
    assert CodexSettings.current!().thread_sandbox == ""

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{turn_sandbox_policy: "bad"})
    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "turn_sandbox_policy"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{
        approval_policy: "future-policy",
        thread_sandbox: "future-sandbox",
        turn_sandbox_policy: %{
          type: "futureSandbox",
          nested: %{flag: true}
        }
      }
    )

    config = Config.settings!()
    assert config.agent_provider.options["approval_policy"] == "future-policy"
    assert config.agent_provider.options["thread_sandbox"] == "future-sandbox"

    assert :ok = Config.validate!()

    assert {:ok, runtime_settings} = CodexSettings.runtime_settings()

    assert runtime_settings.turn_sandbox_policy == %{
             "type" => "futureSandbox",
             "nested" => %{"flag" => true}
           }

    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_options: %{command: "codex app-server"})
    assert Config.settings!().agent_provider.options["command"] == "codex app-server"
  end

  test "agent_provider codex options configure provider runtime" do
    explicit_policy = %{
      type: "workspaceWrite",
      writableRoots: ["relative/path"],
      networkAccess: true
    }

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{
        command: "codex app-server --model gpt-5.5",
        read_timeout_ms: 12_000,
        approval_policy: %{reject: %{sandbox_approval: true}},
        turn_sandbox_policy: explicit_policy
      }
    )

    config = Config.settings!()

    assert config.agent_provider.kind == "codex"
    assert config.agent_provider.options["command"] == "codex app-server --model gpt-5.5"
    assert config.agent_provider.options["command_argv"] == nil
    assert config.agent_provider.options["read_timeout_ms"] == 12_000
    assert config.agent_provider.options["approval_policy"] == %{"reject" => %{"sandbox_approval" => true}}

    assert config.agent_provider.options["turn_sandbox_policy"] == %{
             "type" => "workspaceWrite",
             "writableRoots" => ["relative/path"],
             "networkAccess" => true
           }

    assert config.agent_provider.options["command"] == "codex app-server --model gpt-5.5"
    assert config.agent_provider.options["read_timeout_ms"] == 12_000
    assert Config.agent_provider_settings().kind == "codex"
    assert SymphonyElixir.AgentProvider.current_kind() == "codex"

    assert {:ok, runtime_settings} = CodexSettings.runtime_settings()
    assert runtime_settings.approval_policy == %{"reject" => %{"sandbox_approval" => true}}
    assert runtime_settings.turn_sandbox_policy == config.agent_provider.options["turn_sandbox_policy"]

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_options: %{
        command: "codex app-server",
        command_argv: ["codex", "app-server", "--model", "gpt 5"]
      }
    )

    config = Config.settings!()
    assert config.agent_provider.options["command"] == "codex app-server"
    assert config.agent_provider.options["command_argv"] == ["codex", "app-server", "--model", "gpt 5"]
  end

  test "agent_provider validates kind and codex option types" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_kind: "claude_code")

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "claude_code",
      agent_provider_options: %{command_argv: ["claude"], prompt_transport: "stream_json"}
    )

    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "codex",
      agent_provider_options: %{read_timeout_ms: "bad"}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "read_timeout_ms"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "codex",
      agent_provider_options: %{prompt_transport: "stdin"}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "prompt_transport"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "codex",
      agent_provider_options: %{command_argv: []}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "command_argv"
    assert message =~ "must not be empty"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "codex",
      agent_provider_options: %{command_argv: ["codex", " ", "app-server"]}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "command_argv"
    assert message =~ "can't be blank"

    assert {:error, %Ecto.Changeset{} = changeset} =
             CodexSettings.validate_options(%{"command" => "codex\napp-server"})

    assert {"must not contain newline, carriage return, or NUL bytes", _meta} = changeset.errors[:command]

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "codex",
      agent_provider_options: %{unknown_option: true}
    )

    assert {:error, {:invalid_workflow_config, message}} = Config.validate!()
    assert message =~ "agent_provider.options"
    assert message =~ "unsupported_agent_provider_options"
    assert message =~ "unknown_option"
  end

  test "config preserves observability summary and event store limits" do
    write_workflow_file!(Workflow.workflow_file_path(),
      observability_summary_max_bytes: 256,
      observability_global_event_limit: 120,
      observability_issue_event_limit: 30,
      observability_run_event_limit: 80,
      observability_session_event_limit: 60,
      observability_index_key_limit: 40,
      observability_pending_event_queue_limit: 25
    )

    observability = Config.settings!().observability

    assert observability.summary_max_bytes == 256
    assert observability.global_event_limit == 120
    assert observability.issue_event_limit == 30
    assert observability.run_event_limit == 80
    assert observability.session_event_limit == 60
    assert observability.index_key_limit == 40
    assert observability.pending_event_queue_limit == 25
  end

  test "config resolves $VAR references for env-backed secret and path values" do
    workspace_env_var = "SYMP_WORKSPACE_ROOT_#{System.unique_integer([:positive])}"
    api_key_env_var = "SYMP_LINEAR_API_KEY_#{System.unique_integer([:positive])}"
    bootstrap_automation_env_var = "SYMP_BOOTSTRAP_AUTOMATION_#{System.unique_integer([:positive])}"
    workspace_root = Path.join("/tmp", "symphony-workspace-root")
    bootstrap_automation = Path.join(["/tmp", "symphony-automation", ".codex"])
    api_key = "resolved-secret"
    codex_bin = Path.join(["~", "bin", "codex"])

    previous_workspace_root = System.get_env(workspace_env_var)
    previous_api_key = System.get_env(api_key_env_var)
    previous_bootstrap_automation = System.get_env(bootstrap_automation_env_var)

    System.put_env(workspace_env_var, workspace_root)
    System.put_env(api_key_env_var, api_key)
    System.put_env(bootstrap_automation_env_var, bootstrap_automation)

    on_exit(fn ->
      restore_env(workspace_env_var, previous_workspace_root)
      restore_env(api_key_env_var, previous_api_key)
      restore_env(bootstrap_automation_env_var, previous_bootstrap_automation)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: "$#{api_key_env_var}",
      workspace_root: "$#{workspace_env_var}",
      workspace_bootstrap_automation_from: "$#{bootstrap_automation_env_var}",
      agent_provider_options: %{command: "#{codex_bin} app-server"}
    )

    config = Config.settings!()
    assert TrackerConfig.api_key(config.tracker) == api_key
    assert config.workspace.root == Path.expand(workspace_root)
    assert config.workspace.bootstrap_automation_from == Path.expand(bootstrap_automation)
    assert config.agent_provider.options["command"] == "#{codex_bin} app-server"
  end

  test "config resolves $VAR references for repo branch and label values" do
    branch_env_var = "SYMP_REPO_BASE_BRANCH_#{System.unique_integer([:positive])}"
    work_prefix_env_var = "SYMP_REPO_BRANCH_WORK_PREFIX_#{System.unique_integer([:positive])}"
    label_env_var = "SYMP_REPO_PR_LABEL_#{System.unique_integer([:positive])}"
    provider_repo_env_var = "SYMP_REPO_PROVIDER_REPOSITORY_#{System.unique_integer([:positive])}"
    provider_api_env_var = "SYMP_REPO_PROVIDER_API_#{System.unique_integer([:positive])}"
    provider_web_env_var = "SYMP_REPO_PROVIDER_WEB_#{System.unique_integer([:positive])}"

    previous_branch = System.get_env(branch_env_var)
    previous_work_prefix = System.get_env(work_prefix_env_var)
    previous_label = System.get_env(label_env_var)
    previous_provider_repo = System.get_env(provider_repo_env_var)
    previous_provider_api = System.get_env(provider_api_env_var)
    previous_provider_web = System.get_env(provider_web_env_var)

    System.put_env(branch_env_var, "master")
    System.put_env(work_prefix_env_var, "ticket/work")
    System.put_env(label_env_var, "release-ready")
    System.put_env(provider_repo_env_var, "acme/widgets")
    System.put_env(provider_api_env_var, "https://api.github.example.test")
    System.put_env(provider_web_env_var, "https://github.example.test")

    on_exit(fn ->
      restore_env(branch_env_var, previous_branch)
      restore_env(work_prefix_env_var, previous_work_prefix)
      restore_env(label_env_var, previous_label)
      restore_env(provider_repo_env_var, previous_provider_repo)
      restore_env(provider_api_env_var, previous_provider_api)
      restore_env(provider_web_env_var, previous_provider_web)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      repo_base_branch: "$#{branch_env_var}",
      repo_branch_work_prefix: "$#{work_prefix_env_var}",
      repo_provider_required_pr_label: "$#{label_env_var}",
      repo_provider_repository: "$#{provider_repo_env_var}",
      repo_provider_api_base_url: "$#{provider_api_env_var}",
      repo_provider_web_base_url: "$#{provider_web_env_var}"
    )

    config = Config.settings!()
    assert config.repo.base_branch == "master"
    assert config.repo.branch.work_prefix == "ticket/work"
    assert config.repo.provider.kind == "github"
    assert config.repo.provider.repository == "acme/widgets"
    assert config.repo.provider.api_base_url == "https://api.github.example.test"
    assert config.repo.provider.web_base_url == "https://github.example.test"
    assert SymphonyElixir.RepoProvider.Config.option(config.repo, "required_pr_label") == "release-ready"
    assert config.repo.provider.options["required_pr_label"] == "release-ready"
  end

  test "config keeps repo provider required PR label in provider options" do
    label_env_var = "SYMP_REPO_PROVIDER_OPTIONS_LABEL_#{System.unique_integer([:positive])}"
    previous_label = System.get_env(label_env_var)
    System.put_env(label_env_var, "release-ready")

    on_exit(fn ->
      restore_env(label_env_var, previous_label)
    end)

    File.write!(
      Workflow.workflow_file_path(),
      """
      ---
      tracker:
        kind: "linear"
        endpoint: "https://api.linear.app/graphql"
        auth: {"api_key": "token", "api_secret": null}
        provider: {"project_slug": "project", "assignee": null, "platform": {}}
        lifecycle:
          active_states: ["Todo", "In Progress"]
          terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
          state_phase_map: {"Backlog": "backlog", "Todo": "todo", "In Progress": "in_progress", "In Review": "human_review", "Merging": "merging", "Rework": "rework", "Done": "done", "Closed": "canceled", "Cancelled": "canceled", "Canceled": "canceled", "Duplicate": "canceled"}
          raw_state_by_route_key: null
          policy_by_route_key: null
          workflows_by_type: null
      polling:
        interval_ms: 30000
      workspace:
        root: "#{Path.join(System.tmp_dir!(), "symphony_workspaces")}"
        bootstrap_automation_from: null
      worker: {}
      repo:
        base_branch: "main"
        provider:
          kind: "github"
          repository: null
          api_base_url: null
          web_base_url: null
          options:
            required_pr_label: "$#{label_env_var}"
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

    config = Config.settings!()
    assert SymphonyElixir.RepoProvider.Config.option(config.repo, "required_pr_label") == "release-ready"
    assert config.repo.provider.options["required_pr_label"] == "release-ready"
  end

  test "config defaults repo provider to github and accepts supported kinds" do
    write_workflow_file!(Workflow.workflow_file_path(), repo_provider_kind: nil)

    config = Config.settings!()
    assert config.repo.provider.kind == "github"
    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), repo_provider_kind: "cnb")

    config = Config.settings!()
    assert config.repo.provider.kind == "cnb"
    assert :ok = Config.validate!()
  end

  test "config no longer resolves env: references" do
    workspace_env_var = "SYMP_WORKSPACE_ROOT_#{System.unique_integer([:positive])}"
    api_key_env_var = "SYMP_LINEAR_API_KEY_#{System.unique_integer([:positive])}"
    workspace_root = Path.join("/tmp", "symphony-workspace-root")
    api_key = "resolved-secret"

    previous_workspace_root = System.get_env(workspace_env_var)
    previous_api_key = System.get_env(api_key_env_var)

    System.put_env(workspace_env_var, workspace_root)
    System.put_env(api_key_env_var, api_key)

    on_exit(fn ->
      restore_env(workspace_env_var, previous_workspace_root)
      restore_env(api_key_env_var, previous_api_key)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: "env:#{api_key_env_var}",
      workspace_root: "env:#{workspace_env_var}"
    )

    config = Config.settings!()
    assert TrackerConfig.api_key(config.tracker) == "env:#{api_key_env_var}"
    assert config.workspace.root == "env:#{workspace_env_var}"
  end

  test "config supports per-state max concurrent agent overrides" do
    workflow = """
    ---
    agent:
      execution:
        max_concurrent_agents: 10
        max_concurrent_agents_by_state:
          todo: 1
          "In Progress": 4
          "In Review": 2
    ---
    """

    File.write!(Workflow.workflow_file_path(), workflow)

    assert Config.settings!().agent.execution.max_concurrent_agents == 10
    assert Config.max_concurrent_agents_for_state("Todo") == 1
    assert Config.max_concurrent_agents_for_state("In Progress") == 4
    assert Config.max_concurrent_agents_for_state("In Review") == 2
    assert Config.max_concurrent_agents_for_state("Closed") == 10
    assert Config.max_concurrent_agents_for_state(:not_a_string) == 10

    write_workflow_file!(Workflow.workflow_file_path(),
      worker_max_concurrent_local_agents: 2,
      worker_max_concurrent_agents_per_host: 2,
      worker_ssh_hosts: ["worker-a"]
    )

    assert :ok = Config.validate!()
    assert Config.settings!().worker.max_concurrent_local_agents == 2
    assert Config.settings!().worker.max_concurrent_agents_per_host == 2
  end

  test "schema helpers cover custom type and state limit validation" do
    assert StringOrMap.type() == :map
    assert StringOrMap.embed_as(:json) == :self
    assert StringOrMap.equal?(%{"a" => 1}, %{"a" => 1})
    refute StringOrMap.equal?(%{"a" => 1}, %{"a" => 2})

    assert {:ok, "value"} = StringOrMap.cast("value")
    assert {:ok, %{"a" => 1}} = StringOrMap.cast(%{"a" => 1})
    assert :error = StringOrMap.cast(123)

    assert {:ok, "value"} = StringOrMap.load("value")
    assert :error = StringOrMap.load(123)

    assert {:ok, %{"a" => 1}} = StringOrMap.dump(%{"a" => 1})
    assert :error = StringOrMap.dump(123)

    assert StateLimits.normalize(nil) == %{}

    assert StateLimits.normalize(%{"In Progress" => 2, todo: 1}) == %{
             "todo" => 1,
             "in progress" => 2
           }

    changeset =
      {%{}, %{limits: :map}}
      |> Changeset.cast(%{limits: %{"" => 1, "todo" => 0}}, [:limits])
      |> StateLimits.validate(:limits)

    assert changeset.errors == [
             limits: {"state names must not be blank", []},
             limits: {"limits must be positive integers", []}
           ]
  end

  test "tracker lifecycle schema rejects unsupported fields generically" do
    changeset =
      Schema.Tracker.changeset(%Schema.Tracker{}, %{
        lifecycle: %{
          "unsupported_field" => true,
          "workflows_by_type" => %{
            "feature" => %{"another_unsupported_field" => true}
          }
        }
      })

    refute changeset.valid?
    assert {:lifecycle, {"contains unsupported field: \"unsupported_field\"", []}} in changeset.errors

    nested_changeset =
      Schema.Tracker.changeset(%Schema.Tracker{}, %{
        lifecycle: %{
          "workflows_by_type" => %{
            "feature" => %{"another_unsupported_field" => true}
          }
        }
      })

    refute nested_changeset.valid?

    assert {:lifecycle, {"contains unsupported workflow field for \"feature\": \"another_unsupported_field\"", []}} in nested_changeset.errors
  end

  test "schema parse normalizes policy keys and env-backed defaults" do
    missing_workspace_env = "SYMP_MISSING_WORKSPACE_#{System.unique_integer([:positive])}"
    empty_secret_env = "SYMP_EMPTY_SECRET_#{System.unique_integer([:positive])}"
    missing_secret_env = "SYMP_MISSING_SECRET_#{System.unique_integer([:positive])}"

    previous_missing_workspace_env = System.get_env(missing_workspace_env)
    previous_empty_secret_env = System.get_env(empty_secret_env)
    previous_missing_secret_env = System.get_env(missing_secret_env)
    previous_linear_api_key = System.get_env("LINEAR_API_KEY")

    System.delete_env(missing_workspace_env)
    System.put_env(empty_secret_env, "")
    System.delete_env(missing_secret_env)
    System.put_env("LINEAR_API_KEY", "env-linear-token")

    on_exit(fn ->
      restore_env(missing_workspace_env, previous_missing_workspace_env)
      restore_env(empty_secret_env, previous_empty_secret_env)
      restore_env(missing_secret_env, previous_missing_secret_env)
      restore_env("LINEAR_API_KEY", previous_linear_api_key)
    end)

    assert {:ok, settings} =
             Schema.parse(%{
               tracker: %{kind: "linear", auth: %{"api_key" => "$#{empty_secret_env}"}},
               workspace: %{root: "$#{missing_workspace_env}"},
               agent_provider: %{
                 kind: "codex",
                 options: %{approval_policy: %{reject: %{sandbox_approval: true}}}
               }
             })

    assert TrackerConfig.api_key(settings.tracker) == nil
    assert settings.workspace.root == Path.join(System.tmp_dir!(), "symphony_workspaces")

    assert settings.agent_provider.options["approval_policy"] == %{
             "reject" => %{"sandbox_approval" => true}
           }

    assert {:ok, settings} =
             Schema.parse(%{
               tracker: %{kind: "linear", auth: %{"api_key" => "$#{missing_secret_env}"}},
               workspace: %{root: ""}
             })

    assert TrackerConfig.api_key(settings.tracker) == "env-linear-token"
    assert settings.workspace.root == Path.join(System.tmp_dir!(), "symphony_workspaces")
  end

  test "schema parse resolves TAPD platform env references and defaults" do
    workspace_env = "SYMP_TAPD_WORKSPACE_#{System.unique_integer([:positive])}"
    author_env = "SYMP_TAPD_AUTHOR_#{System.unique_integer([:positive])}"

    previous_workspace_env = System.get_env(workspace_env)
    previous_author_env = System.get_env(author_env)

    System.put_env(workspace_env, "53000000")
    System.put_env(author_env, "symphony")

    on_exit(fn ->
      restore_env(workspace_env, previous_workspace_env)
      restore_env(author_env, previous_author_env)
    end)

    assert {:ok, settings} =
             Schema.parse(%{
               tracker: %{
                 kind: "tapd",
                 provider: %{"platform" => %{"workspace_id" => "$#{workspace_env}"}}
               }
             })

    assert get_in(TrackerConfig.provider(settings.tracker), ["platform", "workspace_id"]) == "53000000"

    assert {:ok, settings} =
             Schema.parse(%{
               tracker: %{
                 kind: "tapd",
                 provider: %{"platform" => %{}}
               }
             })

    assert get_in(TrackerConfig.provider(settings.tracker), ["platform", "comment_author"]) == nil

    assert {:ok, settings} =
             Schema.parse(%{
               tracker: %{
                 kind: "tapd",
                 provider: %{"platform" => %{"comment_author" => "$#{author_env}"}}
               }
             })

    assert get_in(TrackerConfig.provider(settings.tracker), ["platform", "comment_author"]) == "symphony"
  end

  test "schema resolves sandbox policies from explicit and default workspaces" do
    explicit_policy = %{"type" => "workspaceWrite", "writableRoots" => ["/tmp/explicit"]}

    assert Schema.resolve_turn_sandbox_policy(%Schema{
             agent_provider: %Schema.AgentProvider{
               kind: "codex",
               options: %{"turn_sandbox_policy" => explicit_policy}
             },
             workspace: %Schema.Workspace{root: "/tmp/ignored"}
           }) == explicit_policy

    assert Schema.resolve_turn_sandbox_policy(%Schema{
             agent_provider: %Schema.AgentProvider{kind: "codex", options: %{}},
             workspace: %Schema.Workspace{root: ""}
           }) == %{
             "type" => "workspaceWrite",
             "writableRoots" => [Path.expand(Path.join(System.tmp_dir!(), "symphony_workspaces"))],
             "readOnlyAccess" => %{"type" => "fullAccess"},
             "networkAccess" => false,
             "excludeTmpdirEnvVar" => false,
             "excludeSlashTmp" => false
           }

    assert Schema.resolve_turn_sandbox_policy(
             %Schema{
               agent_provider: %Schema.AgentProvider{kind: "codex", options: %{}},
               workspace: %Schema.Workspace{root: "/tmp/ignored"}
             },
             "/tmp/workspace"
           ) == %{
             "type" => "workspaceWrite",
             "writableRoots" => [Path.expand("/tmp/workspace")],
             "readOnlyAccess" => %{"type" => "fullAccess"},
             "networkAccess" => false,
             "excludeTmpdirEnvVar" => false,
             "excludeSlashTmp" => false
           }
  end

  test "schema keeps workspace roots raw while sandbox helpers expand only for local use" do
    assert {:ok, settings} =
             Schema.parse(%{workspace: %{root: "~/.symphony-workspaces"}})

    assert settings.workspace.root == "~/.symphony-workspaces"

    assert Schema.resolve_turn_sandbox_policy(settings) == %{
             "type" => "workspaceWrite",
             "writableRoots" => [Path.expand("~/.symphony-workspaces")],
             "readOnlyAccess" => %{"type" => "fullAccess"},
             "networkAccess" => false,
             "excludeTmpdirEnvVar" => false,
             "excludeSlashTmp" => false
           }

    assert {:ok, remote_policy} =
             Schema.resolve_runtime_turn_sandbox_policy(settings, nil, remote: true)

    assert remote_policy == %{
             "type" => "workspaceWrite",
             "writableRoots" => ["~/.symphony-workspaces"],
             "readOnlyAccess" => %{"type" => "fullAccess"},
             "networkAccess" => false,
             "excludeTmpdirEnvVar" => false,
             "excludeSlashTmp" => false
           }
  end

  test "runtime sandbox policy resolution passes explicit policies through unchanged" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-runtime-sandbox-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      issue_workspace = Path.join(workspace_root, "MT-100")
      File.mkdir_p!(issue_workspace)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{
          turn_sandbox_policy: %{
            type: "workspaceWrite",
            writableRoots: ["relative/path"],
            networkAccess: true
          }
        }
      )

      assert {:ok, runtime_settings} = CodexSettings.runtime_settings(issue_workspace)

      assert runtime_settings.turn_sandbox_policy == %{
               "type" => "workspaceWrite",
               "writableRoots" => ["relative/path"],
               "networkAccess" => true
             }

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{
          turn_sandbox_policy: %{
            type: "futureSandbox",
            nested: %{flag: true}
          }
        }
      )

      assert {:ok, runtime_settings} = CodexSettings.runtime_settings(issue_workspace)

      assert runtime_settings.turn_sandbox_policy == %{
               "type" => "futureSandbox",
               "nested" => %{"flag" => true}
             }
    after
      File.rm_rf(test_root)
    end
  end

  test "path safety returns errors for invalid path segments" do
    invalid_segment = String.duplicate("a", 300)
    path = Path.join(System.tmp_dir!(), invalid_segment)
    expanded_path = Path.expand(path)

    assert {:error, {:path_canonicalize_failed, ^expanded_path, :enametoolong}} =
             SymphonyElixir.PathSafety.canonicalize(path)
  end

  test "runtime sandbox policy resolution defaults when omitted and ignores workspace for explicit policies" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-runtime-sandbox-branches-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      issue_workspace = Path.join(workspace_root, "MT-101")

      File.mkdir_p!(issue_workspace)

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      settings = Config.settings!()

      assert {:ok, canonical_workspace_root} =
               SymphonyElixir.PathSafety.canonicalize(workspace_root)

      assert {:ok, default_policy} = Schema.resolve_runtime_turn_sandbox_policy(settings)
      assert default_policy["type"] == "workspaceWrite"
      assert default_policy["writableRoots"] == [canonical_workspace_root]

      assert {:ok, blank_workspace_policy} =
               Schema.resolve_runtime_turn_sandbox_policy(settings, "")

      assert blank_workspace_policy == default_policy

      read_only_settings =
        put_in(
          settings.agent_provider.options["turn_sandbox_policy"],
          %{"type" => "readOnly", "networkAccess" => true}
        )

      assert {:ok, %{"type" => "readOnly", "networkAccess" => true}} =
               Schema.resolve_runtime_turn_sandbox_policy(read_only_settings, 123)

      future_settings =
        put_in(
          settings.agent_provider.options["turn_sandbox_policy"],
          %{"type" => "futureSandbox", "nested" => %{"flag" => true}}
        )

      assert {:ok, %{"type" => "futureSandbox", "nested" => %{"flag" => true}}} =
               Schema.resolve_runtime_turn_sandbox_policy(future_settings, 123)

      assert {:error, {:unsafe_turn_sandbox_policy, {:invalid_workspace_root, 123}}} =
               Schema.resolve_runtime_turn_sandbox_policy(settings, 123)
    after
      File.rm_rf(test_root)
    end
  end

  test "workflow prompt is used when building base prompt" do
    workflow_prompt = "Workflow prompt body used as codex instruction."

    write_workflow_file!(Workflow.workflow_file_path(), prompt: workflow_prompt)
    assert Config.workflow_prompt() == workflow_prompt
  end

  test "workflow prompt can render generated typed tool inventory" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "{{ tool_inventory }}")

    prompt =
      SymphonyElixir.Workflow.Prompt.Builder.build_prompt(%{id: "issue-1"},
        tool_context: %{
          tool_specs: [
            %{
              "name" => "linear_issue_snapshot",
              "description" => "Read issue snapshot.",
              "inputSchema" => %{"type" => "object"}
            }
          ],
          tool_metadata: %{
            "linear_issue_snapshot" => %{
              "workflowCapability" => "tracker.issue_snapshot",
              "sideEffect" => "read_only",
              "sourceKind" => "linear",
              "schemaVersion" => "1"
            }
          }
        }
      )

    assert prompt =~ "## Typed Workflow Tool Inventory"
    assert prompt =~ "`tracker.issue_snapshot`"
    assert prompt =~ "`linear_issue_snapshot`"
  end

  test "workflow prompt renders Claude Code MCP tool names in typed inventory" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "{{ tool_inventory }}")

    prompt =
      SymphonyElixir.Workflow.Prompt.Builder.build_prompt(%{id: "issue-1"},
        agent_provider_kind: "claude_code",
        tool_context: %{
          tool_specs: [
            %{
              "name" => "linear_issue_snapshot",
              "description" => "Read issue snapshot.",
              "inputSchema" => %{"type" => "object"}
            }
          ],
          tool_metadata: %{
            "linear_issue_snapshot" => %{
              "workflowCapability" => "tracker.issue_snapshot",
              "sideEffect" => "read_only",
              "sourceKind" => "linear",
              "schemaVersion" => "1"
            }
          }
        }
      )

    assert prompt =~ "`mcp__symphony-planned-tools__linear_issue_snapshot`"
    assert prompt =~ "`linear_issue_snapshot`"
  end

  test "workflow prompt renders explicit typed tool operator migration fallback policy" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "{{ tool_inventory }}")

    prompt =
      SymphonyElixir.Workflow.Prompt.Builder.build_prompt(%{id: "issue-1"},
        tool_context: %{
          tool_specs: [
            %{
              "name" => "legacy_tracker_api",
              "description" => "Execute legacy tracker API.",
              "inputSchema" => %{"type" => "object"}
            }
          ],
          tool_metadata: %{
            "legacy_tracker_api" => %{
              "sideEffect" => "destructive",
              "sourceKind" => "legacy_tracker",
              "schemaVersion" => "1"
            }
          }
        },
        typed_workflow_tool_fallback_policy: %{
          "tracker.issue_snapshot" => %{"tool" => "legacy_tracker_api", "reason" => "temporary migration"}
        }
      )

    assert prompt =~ "## Typed Workflow Tool Inventory"
    assert prompt =~ "`tracker.issue_snapshot`"
    assert prompt =~ "`legacy_tracker_api`"
    assert prompt =~ "explicit operator migration fallback permitted: temporary migration"
  end

  test "remote workspace lifecycle uses ssh host aliases from worker config" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-remote-workspace-#{System.unique_integer([:positive])}"
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
      fake_scp = Path.join(test_root, "scp")
      workspace_root = "~/.symphony-remote-workspaces"
      workspace_path = "/remote/home/.symphony-remote-workspaces/MT-SSH-WS"
      automation_pack = Path.join([test_root, "automation", ".codex"])

      File.mkdir_p!(test_root)
      File.mkdir_p!(Path.join([automation_pack, "skills", "repo", "land"]))

      File.write!(
        Path.join([automation_pack, "skills", "repo", "land", "SKILL.md"]),
        "# remote automation skill\n"
      )

      System.put_env("SYMP_TEST_SSH_TRACE", trace_file)
      System.put_env("PATH", test_root <> ":" <> (previous_path || ""))

      File.write!(fake_ssh, """
      #!/bin/sh
      trace_file="${SYMP_TEST_SSH_TRACE:-/tmp/symphony-fake-ssh.trace}"
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"

      case "$*" in
        *"__SYMPHONY_WORKSPACE__"*)
          printf '%s\\t%s\\t%s\\t%s\\n' '__SYMPHONY_WORKSPACE__' '1' '/remote/home/.symphony-remote-workspaces' '#{workspace_path}'
          ;;
        *"__SYMPHONY_WORKSPACE_MISSING__"*)
          printf '%s\\t%s\\t%s\\t%s\\n' '__SYMPHONY_WORKSPACE__' '0' '/remote/home/.symphony-remote-workspaces' '#{workspace_path}'
          ;;
      esac

      exit 0
      """)

      File.chmod!(fake_ssh, 0o755)

      File.write!(fake_scp, """
      #!/bin/sh
      trace_file="${SYMP_TEST_SSH_TRACE:-/tmp/symphony-fake-ssh.trace}"
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"
      exit 0
      """)

      File.chmod!(fake_scp, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        workspace_bootstrap_automation_from: automation_pack,
        worker_ssh_hosts: ["worker-01:2200"],
        hook_before_run: "echo before-run",
        hook_after_run: "echo after-run",
        hook_before_remove: "echo before-remove"
      )

      assert Config.settings!().worker.ssh_hosts == ["worker-01:2200"]
      assert Config.settings!().workspace.root == workspace_root
      assert {:ok, ^workspace_path} = Workspace.create_for_issue("MT-SSH-WS", "worker-01:2200")
      assert :ok = Workspace.run_before_run_hook(workspace_path, "MT-SSH-WS", "worker-01:2200")
      assert :ok = Workspace.run_after_run_hook(workspace_path, "MT-SSH-WS", "worker-01:2200")
      assert :ok = Workspace.remove_issue_workspaces("MT-SSH-WS", "worker-01:2200")

      trace = File.read!(trace_file)
      assert trace =~ "-p 2200 worker-01 bash -lc"
      assert trace =~ "-P 2200"
      assert trace =~ "__SYMPHONY_WORKSPACE__"
      assert trace =~ "~/.symphony-remote-workspaces/MT-SSH-WS"
      assert trace =~ "${workspace#\\~/}"
      assert trace =~ "if [ \"$canonical_workspace\" = \"$canonical_root\" ]; then\n  printf"
      assert trace =~ "workspace_within_root=0\nif [ \"$canonical_root\" = "
      assert trace =~ "case \"$canonical_workspace\" in\n    \"$canonical_root\"/*) workspace_within_root=1 ;;"
      assert trace =~ automation_pack

      assert trace =~
               "worker-01:/remote/home/.symphony-remote-workspaces/.symphony-bootstrap-MT-SSH-WS"

      assert trace =~ "echo before-run"
      assert trace =~ "echo after-run"
      assert trace =~ "echo before-remove"
      assert trace =~ "SYMPHONY_WORKSPACE_AUTOMATION_DIR"
      assert trace =~ "/remote/home/.symphony-remote-workspaces/MT-SSH-WS/.codex"
      assert trace =~ "rm -rf"
      assert trace =~ workspace_path
    after
      File.rm_rf(test_root)
    end
  end

  test "remote workspace cleanup uses the recorded workspace path when workflow root changes" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-remote-workspace-recorded-cleanup-#{System.unique_integer([:positive])}"
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
      recorded_workspace_path = "/remote/home/.recorded-root/MT-SSH-RECORDED"

      File.mkdir_p!(test_root)
      System.put_env("SYMP_TEST_SSH_TRACE", trace_file)
      System.put_env("PATH", test_root <> ":" <> (previous_path || ""))

      File.write!(fake_ssh, """
      #!/bin/sh
      trace_file="${SYMP_TEST_SSH_TRACE:-/tmp/symphony-fake-ssh.trace}"
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"

      case "$*" in
        *"__SYMPHONY_WORKSPACE__"*)
          printf '%s\\t%s\\t%s\\t%s\\n' '__SYMPHONY_WORKSPACE__' '0' '/remote/home/.recorded-root' '#{recorded_workspace_path}'
          ;;
      esac

      exit 0
      """)

      File.chmod!(fake_ssh, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: "~/.initial-root",
        worker_ssh_hosts: ["worker-01:2200"]
      )

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: "~/.current-root",
        worker_ssh_hosts: ["worker-01:2200"]
      )

      assert :ok =
               Workspace.remove_issue_workspaces(
                 "MT-SSH-RECORDED",
                 "worker-01:2200",
                 recorded_workspace_path
               )

      trace = File.read!(trace_file)
      assert trace =~ "-p 2200 worker-01 bash -lc"
      assert trace =~ recorded_workspace_path
      assert trace =~ "/remote/home/.recorded-root"
      assert trace =~ "rm -rf"
      refute trace =~ "~/.current-root"
    after
      File.rm_rf(test_root)
    end
  end

  test "remote workspace rejects canonical paths outside the configured root" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-remote-workspace-boundary-#{System.unique_integer([:positive])}"
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
      printf '%s\\t%s\\t%s\\t%s\\n' '__SYMPHONY_WORKSPACE_ERROR__' 'workspace_outside_root' '/remote/home/.symphony-remote-workspaces' '/tmp/outside'
      exit 73
      """)

      File.chmod!(fake_ssh, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: "~/.symphony-remote-workspaces",
        worker_ssh_hosts: ["worker-01:2200"]
      )

      assert {:error, {:workspace_outside_root, "/tmp/outside", "/remote/home/.symphony-remote-workspaces"}} =
               Workspace.create_for_issue("MT-SSH-ESCAPE", "worker-01:2200")
    after
      File.rm_rf(test_root)
    end
  end

  defp sort_issues_for_dispatch(issues) do
    Dispatch.sort_issues_for_dispatch(issues)
  end

  defp should_dispatch_issue(issue, state) do
    Dispatch.should_dispatch_issue?(
      issue,
      OrchestratorRuntime.dispatch_runtime(state),
      OrchestratorRuntime.dispatch_context()
    )
  end

  defp prepare_issue_for_dispatch(issue, fetcher, state_updater) do
    Dispatch.prepare_issue_for_dispatch(
      issue,
      fetcher,
      state_updater,
      OrchestratorRuntime.dispatch_context(),
      emit_route_transition: &OrchestratorEvents.emit_route_transition/7
    )
  end

  defp revalidate_issue_for_dispatch(issue, fetcher) do
    Dispatch.revalidate_issue_for_dispatch(issue, fetcher, OrchestratorRuntime.dispatch_context())
  end
end
