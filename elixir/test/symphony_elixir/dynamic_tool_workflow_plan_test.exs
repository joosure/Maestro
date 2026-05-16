defmodule SymphonyElixir.Agent.DynamicTool.WorkflowPlanTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Bridge
  alias SymphonyElixir.Agent.DynamicTool.BridgeRegistry
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.WorkflowPlan
  alias SymphonyElixir.AgentProvider.OpenCode.Tooling, as: OpenCodeTooling
  alias SymphonyElixir.Observability.EventStore

  setup do
    ensure_named_process!(BridgeRegistry)
    ensure_named_process!(EventStore)
    :ok
  end

  test "restricts exposed tools to current workflow-required capabilities" do
    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
               tool_context: full_tool_context()
             )

    names = tool_names(context)

    assert "linear_issue_snapshot" in names
    assert "linear_move_issue" in names
    assert "linear_upsert_workpad" in names
    assert "linear_attach_change_proposal" in names
    assert "repo_checkout" in names
    assert "repo_diff" in names
    assert "repo_commit" in names
    assert "repo_push" in names
    assert "repo_change_proposal_snapshot" in names
    assert "repo_create_or_update_change_proposal" in names
    assert "repo_read_change_proposal_discussion" in names
    assert "repo_add_change_proposal_comment" in names
    assert "repo_reply_change_proposal_review_comment" in names
    assert "repo_read_change_proposal_checks" in names

    refute "legacy_tracker_api" in names
    refute "tapd_create_follow_up_story" in names
    refute "tapd_add_story_relation" in names
    refute "tapd_save_story_dependency" in names
    refute "repo_merge_change_proposal" in names
    refute "repo_close_change_proposal" in names
    refute Map.has_key?(context.source_context.routes, "legacy_tracker_api")
  end

  test "adds current execution-profile tools only for the current route" do
    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "Merging", lifecycle_phase: "merging"},
               tool_context: full_tool_context()
             )

    names = tool_names(context)

    assert "repo_merge_change_proposal" in names
    refute "repo_close_change_proposal" in names
  end

  test "permits operator migration fallback only when required typed tool is missing and policy names it" do
    context =
      full_tool_context()
      |> remove_tool("linear_issue_snapshot")

    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
               tool_context: context,
               typed_workflow_tool_fallback_policy: %{
                 "tracker.issue_snapshot" => %{
                   "tool" => "legacy_tracker_api",
                   "reason" => "temporary provider migration"
                 }
               }
             )

    names = tool_names(context)

    assert "legacy_tracker_api" in names
    refute "linear_issue_snapshot" in names
    assert context.tool_plan.exposure == "workflow_required"
  end

  test "registered bridge token reuses the restricted context for execution" do
    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
               tool_context: full_tool_context()
             )

    token = Bridge.register_context(context)

    try do
      assert Bridge.valid_token?(token)

      assert %{
               "success" => false,
               "payload" => %{"error" => %{"supportedTools" => supported_tools}}
             } =
               Bridge.execute(
                 "legacy_tracker_api",
                 %{"operation" => "viewer"},
                 Bridge.put_token_context([], token)
               )

      refute "legacy_tracker_api" in supported_tools
      assert "linear_issue_snapshot" in supported_tools
    after
      Bridge.unregister_context(token)
    end
  end

  test "dynamic tool capture reuses workflow-restricted context" do
    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
               tool_context: full_tool_context()
             )

    captured_context = DynamicTool.capture_context(tool_context: context)
    names = tool_names(captured_context)

    assert "linear_issue_snapshot" in names
    refute "legacy_tracker_api" in names
    refute "repo_merge_change_proposal" in names
  end

  test "normal TAPD workflow sessions do not expose retired raw TAPD API or diagnostics" do
    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
               tool_context: tapd_tool_context()
             )

    names = tool_names(context)

    assert "tapd_issue_snapshot" in names
    assert "tapd_move_issue" in names
    assert "tapd_upsert_workpad" in names
    assert "tapd_attach_change_proposal" in names
    assert "repo_create_or_update_change_proposal" in names
    refute "tapd_api" in names
    refute "tapd_provider_diagnostics" in names
    refute "repo_merge_change_proposal" in names
  end

  test "diagnostics exposure includes only fixed provider diagnostics" do
    assert {:ok, context} =
             WorkflowPlan.from_opts(
               dynamic_tool_exposure: :diagnostics,
               tool_context: tapd_tool_context()
             )

    names = tool_names(context)

    assert context.tool_plan.exposure == "diagnostics"
    assert "tapd_provider_diagnostics" in names
    refute "tapd_api" in names
    refute "tapd_issue_snapshot" in names
    refute "repo_create_or_update_change_proposal" in names
  end

  test "retired raw TAPD API fails closed without invoking a provider request" do
    test_pid = self()

    assert %{
             "success" => false,
             "payload" => %{
               "error" => %{
                 "code" => "unsupported_tool",
                 "supportedTools" => supported_tools
               }
             }
           } =
             Bridge.execute(
               "tapd_api",
               %{"method" => "GET", "path" => "/stories", "params" => %{}},
               tool_context: tapd_tool_context(),
               request_fun: fn request ->
                 send(test_pid, {:unexpected_tapd_request, request})
                 {:ok, %{}}
               end
             )

    refute "tapd_api" in supported_tools
    assert "tapd_provider_diagnostics" in supported_tools
    refute_received {:unexpected_tapd_request, _request}
  end

  test "all-tools diagnostic capture does not reintroduce retired raw TAPD API" do
    assert {:ok, context} =
             WorkflowPlan.from_opts(
               dynamic_tool_exposure: :all,
               tool_context: tapd_tool_context()
             )

    refute "tapd_api" in tool_names(context)

    assert %{
             "success" => false,
             "payload" => %{
               "error" => %{
                 "code" => "unsupported_tool",
                 "supportedTools" => supported_tools
               }
             }
           } =
             Bridge.execute(
               "tapd_api",
               %{"method" => "GET", "path" => "/stories", "params" => %{}},
               tool_context: context
             )

    refute "tapd_api" in supported_tools
  end

  test "retired raw tool attempts emit structured unsupported-tool audit fields" do
    EventStore.reset()

    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
               tool_context: tapd_tool_context()
             )

    capture_log(fn ->
      Bridge.execute(
        "tapd_api",
        %{"method" => "GET", "path" => "/stories"},
        tool_context: context,
        agent_provider_kind: "claude_code",
        run_id: "run-retired-raw"
      )
    end)

    event =
      EventStore.recent_events(limit: 20)
      |> Enum.find(&(&1["event"] == "tool_call_rejected" and &1["tool_name"] == "tapd_api"))

    assert event["dynamic_tool_failure_reason"] == "unsupported_tool"
    assert event["dynamic_tool_rejection_reason"] == "unsupported_tool"
    assert event["dynamic_tool_usage_kind"] == "raw"
    assert event["dynamic_tool_exposure"] == "workflow_required"
    assert event["agent_provider_kind"] == "claude_code"
    assert event["run_id"] == "run-retired-raw"
  end

  test "workflow-planned tool surface stays stable across retry attempts" do
    opts = [
      workflow_settings: workflow_settings(),
      issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
      tool_context: tapd_tool_context()
    ]

    assert {:ok, first_attempt} = WorkflowPlan.from_opts(Keyword.put(opts, :retry_attempt, 1))
    assert {:ok, retry_attempt} = WorkflowPlan.from_opts(Keyword.put(opts, :retry_attempt, 2))

    assert Enum.sort(tool_names(first_attempt)) == Enum.sort(tool_names(retry_attempt))

    assert first_attempt.tool_plan.required_capabilities ==
             retry_attempt.tool_plan.required_capabilities

    refute "tapd_api" in tool_names(retry_attempt)
  end

  test "opencode tooling writes only workflow-planned tools for the retry-safe context" do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "symphony-opencode-planned-tools-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace, ".git"))
    on_exit(fn -> File.rm_rf(workspace) end)

    assert {:ok, context} =
             WorkflowPlan.from_opts(
               workflow_settings: workflow_settings(),
               issue: %{state: "In Progress", lifecycle_phase: "in_progress"},
               tool_context: tapd_tool_context()
             )

    assert :ok = OpenCodeTooling.prepare_workspace(workspace, tool_context: context)

    tool_dir = Path.join([workspace, ".opencode", "tools"])
    files = tool_dir |> File.ls!() |> Enum.sort()

    assert "tapd_issue_snapshot.ts" in files
    assert "repo_create_or_update_change_proposal.ts" in files
    refute "tapd_api.ts" in files
    refute "tapd_provider_diagnostics.ts" in files
    refute "repo_merge_change_proposal.ts" in files
  end

  defp workflow_settings do
    %{
      workflow: %{
        profile: %{
          kind: "coding_pr_delivery",
          version: 1,
          options: %{
            requirements: %{
              change_proposal: true,
              typed_tracker_tools: true,
              typed_repo_tools: true
            },
            execution_profiles: %{
              allowed: ["land"]
            }
          }
        }
      },
      tracker: %{
        lifecycle: %{
          state_phase_map: %{
            "In Progress" => "in_progress",
            "Merging" => "merging"
          }
        }
      }
    }
  end

  defp full_tool_context do
    tool_specs = [
      tool_spec("legacy_tracker_api"),
      tool_spec("linear_issue_snapshot"),
      tool_spec("linear_move_issue"),
      tool_spec("linear_upsert_workpad"),
      tool_spec("linear_attach_change_proposal"),
      tool_spec("tapd_create_follow_up_story"),
      tool_spec("tapd_read_story_relations"),
      tool_spec("tapd_add_story_relation"),
      tool_spec("tapd_read_story_dependencies"),
      tool_spec("tapd_save_story_dependency"),
      tool_spec("repo_checkout"),
      tool_spec("repo_diff"),
      tool_spec("repo_commit"),
      tool_spec("repo_push"),
      tool_spec("repo_change_proposal_snapshot"),
      tool_spec("repo_create_or_update_change_proposal"),
      tool_spec("repo_read_change_proposal_discussion"),
      tool_spec("repo_add_change_proposal_comment"),
      tool_spec("repo_reply_change_proposal_review_comment"),
      tool_spec("repo_read_change_proposal_checks"),
      tool_spec("repo_merge_change_proposal"),
      tool_spec("repo_close_change_proposal")
    ]

    metadata = %{
      "legacy_tracker_api" => %{
        "sideEffect" => "destructive",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      },
      "linear_issue_snapshot" => typed_metadata("tracker.issue_snapshot", "read_only", "linear"),
      "linear_move_issue" => typed_metadata("tracker.move_issue", "write", "linear"),
      "linear_upsert_workpad" => typed_metadata("tracker.upsert_workpad", "write", "linear"),
      "linear_attach_change_proposal" => typed_metadata("tracker.attach_change_proposal", "write", "linear"),
      "tapd_create_follow_up_story" => typed_metadata("tracker.create_follow_up_issue", "write", "tapd"),
      "tapd_read_story_relations" => typed_metadata("tracker.read_issue_relations", "read_only", "tapd"),
      "tapd_add_story_relation" => typed_metadata("tracker.add_issue_relation", "write", "tapd"),
      "tapd_read_story_dependencies" => typed_metadata("tracker.read_issue_dependencies", "read_only", "tapd"),
      "tapd_save_story_dependency" => typed_metadata("tracker.save_issue_dependency", "write", "tapd"),
      "repo_checkout" => typed_metadata("repo.checkout", "write", "git"),
      "repo_diff" => typed_metadata("repo.diff", "read_only", "git"),
      "repo_commit" => typed_metadata("repo.commit", "write", "git"),
      "repo_push" => typed_metadata("repo.push", "write", "git"),
      "repo_change_proposal_snapshot" => typed_metadata("repo.change_proposal_snapshot", "read_only", "github"),
      "repo_create_or_update_change_proposal" => typed_metadata("repo.create_or_update_change_proposal", "write", "github"),
      "repo_read_change_proposal_discussion" => typed_metadata("repo.read_change_proposal_discussion", "read_only", "github"),
      "repo_add_change_proposal_comment" => typed_metadata("repo.add_change_proposal_comment", "write", "github"),
      "repo_reply_change_proposal_review_comment" => typed_metadata("repo.reply_change_proposal_review_comment", "write", "github"),
      "repo_read_change_proposal_checks" => typed_metadata("repo.read_change_proposal_checks", "read_only", "github"),
      "repo_merge_change_proposal" => typed_metadata("repo.merge_change_proposal", "destructive", "github"),
      "repo_close_change_proposal" => typed_metadata("repo.close_change_proposal", "destructive", "github")
    }

    %{
      source: SymphonyElixir.Agent.DynamicTool.CompositeSource,
      source_context: %{
        tool_specs: tool_specs,
        routes:
          Map.new(tool_specs, fn %{"name" => name} ->
            {name, %{source: __MODULE__, source_context: %{}}}
          end),
        sources: [%{source: __MODULE__, source_context: %{}, tool_specs: tool_specs}]
      },
      source_kind: "composite",
      tool_specs: tool_specs,
      tool_metadata: metadata,
      tool_environment: %{}
    }
  end

  defp tapd_tool_context do
    tool_specs = [
      tool_spec("tapd_issue_snapshot"),
      tool_spec("tapd_move_issue"),
      tool_spec("tapd_upsert_workpad"),
      tool_spec("tapd_attach_change_proposal"),
      tool_spec("tapd_provider_diagnostics"),
      tool_spec("tapd_create_follow_up_story"),
      tool_spec("tapd_read_story_relations"),
      tool_spec("tapd_add_story_relation"),
      tool_spec("tapd_read_story_dependencies"),
      tool_spec("tapd_save_story_dependency"),
      tool_spec("repo_checkout"),
      tool_spec("repo_diff"),
      tool_spec("repo_commit"),
      tool_spec("repo_push"),
      tool_spec("repo_change_proposal_snapshot"),
      tool_spec("repo_create_or_update_change_proposal"),
      tool_spec("repo_read_change_proposal_discussion"),
      tool_spec("repo_add_change_proposal_comment"),
      tool_spec("repo_reply_change_proposal_review_comment"),
      tool_spec("repo_read_change_proposal_checks"),
      tool_spec("repo_merge_change_proposal"),
      tool_spec("repo_close_change_proposal")
    ]

    metadata = %{
      "tapd_issue_snapshot" => typed_metadata("tracker.issue_snapshot", "read_only", "tapd"),
      "tapd_move_issue" => typed_metadata("tracker.move_issue", "write", "tapd"),
      "tapd_upsert_workpad" => typed_metadata("tracker.upsert_workpad", "write", "tapd"),
      "tapd_attach_change_proposal" => typed_metadata("tracker.attach_change_proposal", "write", "tapd"),
      "tapd_provider_diagnostics" => typed_metadata("tracker.provider_diagnostics", "read_only", "tapd"),
      "tapd_create_follow_up_story" => typed_metadata("tracker.create_follow_up_issue", "write", "tapd"),
      "tapd_read_story_relations" => typed_metadata("tracker.read_issue_relations", "read_only", "tapd"),
      "tapd_add_story_relation" => typed_metadata("tracker.add_issue_relation", "write", "tapd"),
      "tapd_read_story_dependencies" => typed_metadata("tracker.read_issue_dependencies", "read_only", "tapd"),
      "tapd_save_story_dependency" => typed_metadata("tracker.save_issue_dependency", "write", "tapd"),
      "repo_checkout" => typed_metadata("repo.checkout", "write", "git"),
      "repo_diff" => typed_metadata("repo.diff", "read_only", "git"),
      "repo_commit" => typed_metadata("repo.commit", "write", "git"),
      "repo_push" => typed_metadata("repo.push", "write", "git"),
      "repo_change_proposal_snapshot" => typed_metadata("repo.change_proposal_snapshot", "read_only", "github"),
      "repo_create_or_update_change_proposal" => typed_metadata("repo.create_or_update_change_proposal", "write", "github"),
      "repo_read_change_proposal_discussion" => typed_metadata("repo.read_change_proposal_discussion", "read_only", "github"),
      "repo_add_change_proposal_comment" => typed_metadata("repo.add_change_proposal_comment", "write", "github"),
      "repo_reply_change_proposal_review_comment" => typed_metadata("repo.reply_change_proposal_review_comment", "write", "github"),
      "repo_read_change_proposal_checks" => typed_metadata("repo.read_change_proposal_checks", "read_only", "github"),
      "repo_merge_change_proposal" => typed_metadata("repo.merge_change_proposal", "destructive", "github"),
      "repo_close_change_proposal" => typed_metadata("repo.close_change_proposal", "destructive", "github")
    }

    %{
      source: SymphonyElixir.Agent.DynamicTool.CompositeSource,
      source_context: %{
        tool_specs: tool_specs,
        routes:
          Map.new(tool_specs, fn %{"name" => name} ->
            {name, %{source: __MODULE__, source_context: %{}}}
          end),
        sources: [%{source: __MODULE__, source_context: %{}, tool_specs: tool_specs}]
      },
      source_kind: "composite",
      tool_specs: tool_specs,
      tool_metadata: metadata,
      tool_environment: %{}
    }
  end

  defp tool_spec(name),
    do: %{"name" => name, "description" => name, "inputSchema" => %{"type" => "object"}}

  defp typed_metadata(capability, side_effect, source_kind) do
    %{
      "workflowCapability" => capability,
      "sideEffect" => side_effect,
      "sourceKind" => source_kind,
      "schemaVersion" => "1"
    }
  end

  defp tool_names(context) do
    context
    |> Context.tool_specs()
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  defp remove_tool(context, name) do
    context
    |> update_in(
      [:tool_specs],
      &Enum.reject(&1, fn tool_spec -> Map.get(tool_spec, "name") == name end)
    )
    |> update_in(
      [:source_context, :tool_specs],
      &Enum.reject(&1, fn tool_spec -> Map.get(tool_spec, "name") == name end)
    )
    |> update_in([:source_context, :routes], &Map.delete(&1, name))
    |> update_in([:tool_metadata], &Map.delete(&1, name))
  end

  defp ensure_named_process!(module) do
    case Process.whereis(module) do
      pid when is_pid(pid) -> :ok
      nil -> start_supervised!(module)
    end
  end
end
