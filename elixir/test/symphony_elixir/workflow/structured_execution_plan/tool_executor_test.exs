defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutorTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.Workflow.CapabilityNames
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Aliases, as: ToolAliases
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutor

  @plan_id "plan-test-1"
  @run_id "run-test-1"
  @issue_id "TES-79"
  @profile %{"kind" => "coding_pr_delivery", "version" => 1}
  @created_at "2026-05-20T00:00:00Z"

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "workflow_plan_snapshot returns a bounded canonical plan summary", %{store: store} do
    assert {:ok, _plan} =
             Store.create(
               plan([
                 backend_item("repo.commit",
                   evidence_refs: [
                     evidence_ref("repo_commit", %{"head_sha" => "abc123", "raw_payload_field" => "do-not-render"})
                   ]
                 )
               ]),
               server: store
             )

    assert {:success, %{"data" => %{"success" => true, "plan" => summary, "changed_items" => []}}} =
             ToolExecutor.execute("workflow_plan_snapshot", %{"plan_id" => @plan_id}, server: store)

    assert summary["plan_id"] == @plan_id
    assert summary["revision"] == 1
    assert summary["item_count"] == 1
    assert summary["items_truncated"] == false

    assert [
             %{
               "item_id" => "repo.commit",
               "status" => "pending",
               "evidence_ref_count" => 1,
               "evidence_kinds" => ["repo_commit"]
             } = item_summary
           ] = summary["items"]

    refute Map.has_key?(item_summary, "evidence_refs")
  end

  test "workflow_plan_upsert merges agent-owned informational items", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.commit")]), server: store)

    agent_item = agent_item("agent.follow_up")

    assert {:success,
            %{
              "data" => %{
                "success" => true,
                "plan" => %{"revision" => 2},
                "changed_items" => [%{"item_id" => "agent.follow_up", "owned_by" => "agent"}]
              }
            }} =
             ToolExecutor.execute(
               "workflow_plan_upsert",
               %{"plan_id" => @plan_id, "plan_revision" => 1, "items" => [agent_item]},
               server: store,
               updated_at: "2026-05-20T00:00:01Z"
             )

    assert {:ok, updated_plan} = Store.fetch(@plan_id, server: store)
    assert Enum.map(updated_plan["items"], & &1["item_id"]) == ["repo.commit", "agent.follow_up"]
  end

  test "workflow_plan_upsert creates a canonical plan record", %{store: store} do
    assert {:success,
            %{
              "data" => %{
                "success" => true,
                "plan" => %{"plan_id" => @plan_id, "revision" => 1},
                "changed_items" => [%{"item_id" => "agent.plan"}]
              }
            }} =
             ToolExecutor.execute("workflow_plan_upsert", %{"plan" => plan([agent_item("agent.plan")])}, server: store)

    assert {:ok, %{"plan_id" => @plan_id}} = Store.fetch(@plan_id, server: store)
  end

  test "workflow_plan_upsert rejects attempts to replace profile-owned items", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.commit")]), server: store)

    assert {:failure, %{"error" => %{"code" => "item_update_not_allowed", "details" => %{"item_id" => "repo.commit"}}}} =
             ToolExecutor.execute(
               "workflow_plan_upsert",
               %{"plan_id" => @plan_id, "plan_revision" => 1, "items" => [agent_item("repo.commit")]},
               server: store
             )

    assert {:ok, %{"revision" => 1, "items" => [%{"owned_by" => "backend"}]}} = Store.fetch(@plan_id, server: store)
  end

  test "workflow_plan_update_item rejects critical completion without evidence", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.commit")]), server: store)

    assert {:failure, %{"error" => %{"code" => "missing_required_evidence", "details" => %{"item_id" => "repo.commit"}}}} =
             ToolExecutor.execute(
               "workflow_plan_update_item",
               %{"plan_id" => @plan_id, "item_id" => "repo.commit", "status" => "complete", "plan_revision" => 1},
               server: store
             )

    assert {:ok, %{"items" => [%{"status" => "pending"}]}} = Store.fetch(@plan_id, server: store)
  end

  test "workflow_plan_update_item returns stable revision conflicts", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    assert {:failure,
            %{
              "error" => %{
                "code" => "revision_conflict",
                "details" => %{"current_revision" => 1, "expected_revision" => 2}
              }
            }} =
             ToolExecutor.execute(
               "workflow_plan_update_item",
               %{"plan_id" => @plan_id, "item_id" => "agent.plan", "status" => "in_progress", "plan_revision" => 2},
               server: store
             )
  end

  test "workflow_plan_render_workpad returns a preview without mutating the plan", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    assert {:success,
            %{
              "data" => %{
                "success" => true,
                "plan" => %{"plan_id" => @plan_id, "revision" => 1},
                "changed_items" => [],
                "rendered_workpad" => %{
                  "mode" => "preview",
                  "plan_id" => @plan_id,
                  "plan_revision" => 1,
                  "body" => body,
                  "fingerprint" => fingerprint
                }
              }
            }} =
             ToolExecutor.execute(
               "workflow_plan_render_workpad",
               %{"plan_id" => @plan_id, "plan_revision" => 1, "mode" => "preview"},
               server: store
             )

    assert body =~ "## Structured Execution Plan Workpad"
    assert body =~ "- [ ] `agent.plan`"
    assert is_binary(fingerprint)
    assert {:ok, %{"revision" => 1} = stored_plan} = Store.fetch(@plan_id, server: store)
    refute Map.has_key?(stored_plan, "rendering")
  end

  test "workflow_plan_render_workpad rejects stale revisions and write mode", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    assert {:failure,
            %{
              "error" => %{
                "code" => "revision_conflict",
                "details" => %{"current_revision" => 1, "expected_revision" => 2}
              }
            }} =
             ToolExecutor.execute(
               "workflow_plan_render_workpad",
               %{"plan_id" => @plan_id, "plan_revision" => 2, "mode" => "preview"},
               server: store
             )

    assert {:failure, %{"error" => %{"code" => "invalid_arguments"}}} =
             ToolExecutor.execute(
               "workflow_plan_render_workpad",
               %{"plan_id" => @plan_id, "plan_revision" => 1, "mode" => "write"},
               server: store
             )
  end

  test "provider-facing aliases are normalized at the Dynamic Tool source boundary", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    context =
      DynamicTool.capture_context(
        dynamic_tool_source: DynamicToolSource,
        server: store,
        workflow_settings: workflow_settings("linear")
      )

    tool_specs = DynamicTool.Context.tool_specs(context)
    tool_metadata = DynamicTool.Context.tool_metadata(context)
    alias_spec = Enum.find(tool_specs, &(&1["name"] == "linear_plan_update_item"))
    render_alias_spec = Enum.find(tool_specs, &(&1["name"] == "linear_plan_render_workpad"))

    assert tool_metadata[alias_spec["name"]]["capability"] == CapabilityNames.workflow_plan_update_item()
    assert tool_metadata[render_alias_spec["name"]]["capability"] == CapabilityNames.workflow_plan_render_workpad()

    assert {:ok, ToolAliases.update_item_tool()} ==
             ToolAliases.canonical_name("linear_plan_update_item", [%{provider_key: "linear"}])

    assert {:success, %{"data" => %{"changed_items" => [%{"item_id" => "agent.plan", "status" => "in_progress"}]}}} =
             DynamicTool.execute(
               context,
               "linear_plan_update_item",
               %{"plan_id" => @plan_id, "item_id" => "agent.plan", "status" => "in_progress", "plan_revision" => 1}
             )

    assert {:success, %{"data" => %{"rendered_workpad" => %{"mode" => "preview"}}}} =
             DynamicTool.execute(
               context,
               "linear_plan_render_workpad",
               %{"plan_id" => @plan_id, "plan_revision" => 2, "mode" => "preview"}
             )

    assert {:failure, %{"error" => %{"code" => "unsupported_tool"}}} =
             ToolExecutor.execute("linear_plan_update_item", %{}, server: store)
  end

  test "provider-facing aliases are derived from runtime provider context", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    context =
      DynamicTool.capture_context(
        dynamic_tool_source: DynamicToolSource,
        server: store,
        workflow_settings: workflow_settings("jira")
      )

    assert context |> DynamicTool.Context.tool_specs() |> Enum.any?(&(&1["name"] == "jira_plan_update_item"))

    assert {:ok, ToolAliases.update_item_tool()} ==
             ToolAliases.canonical_name("jira_plan_update_item", [%{provider_key: "jira"}])

    assert {:success, %{"data" => %{"changed_items" => [%{"item_id" => "agent.plan", "status" => "in_progress"}]}}} =
             DynamicTool.execute(
               context,
               "jira_plan_update_item",
               %{"plan_id" => @plan_id, "item_id" => "agent.plan", "status" => "in_progress", "plan_revision" => 1}
             )
  end

  test "provider-facing aliases can be derived from source provider contexts", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    context =
      DynamicTool.capture_context(
        dynamic_tool_source: DynamicToolSource,
        server: store,
        workflow_settings: workflow_settings(nil),
        provider_contexts: [%{"provider_key" => "jira"}]
      )

    assert context |> DynamicTool.Context.tool_specs() |> Enum.any?(&(&1["name"] == "jira_plan_snapshot"))

    assert {:success, %{"data" => %{"plan" => %{"plan_id" => @plan_id}}}} =
             DynamicTool.execute(context, "jira_plan_snapshot", %{"plan_id" => @plan_id})
  end

  test "tool aliases consume normalized provider contexts only" do
    assert :error == ToolAliases.canonical_name("jira_plan_update_item", [%{"provider_key" => "jira"}])

    assert [] ==
             ToolAliases.provider_alias_specs(ToolExecutor.tool_specs(), [
               %{"provider_key" => "jira"}
             ])
  end

  test "tool executor source remains provider-neutral" do
    source =
      Path.expand("../../../../lib/symphony_elixir/workflow/structured_execution_plan/tool_executor.ex", __DIR__)
      |> File.read!()

    refute source =~ "linear_plan_"
    refute source =~ "tapd_plan_"
  end

  test "tool alias core does not hard-code provider aliases" do
    source =
      Path.expand("../../../../lib/symphony_elixir/workflow/structured_execution_plan/tool/aliases.ex", __DIR__)
      |> File.read!()

    refute source =~ "\"linear\""
    refute source =~ "\"tapd\""
    refute source =~ "linear_plan"
    refute source =~ "tapd_plan"
  end

  test "structured plan source stays disabled until workflow profile enables it", %{store: store} do
    context =
      DynamicTool.capture_context(
        dynamic_tool_source: DynamicToolSource,
        server: store,
        workflow_settings: workflow_settings("linear", false)
      )

    assert DynamicTool.Context.tool_specs(context) == []

    assert {:failure, %{"error" => %{"code" => "unsupported_tool"}}} =
             DynamicTool.execute(context, "workflow_plan_snapshot", %{"plan_id" => @plan_id})
  end

  test "explicit planning-only source exposes canonical and provider-facing plan tools without repo or tracker mutation", %{
    store: store
  } do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    context =
      DynamicTool.capture_context(
        dynamic_tool_sources: [
          {DynamicToolSource, %{server: store, workflow_settings: workflow_settings("linear")}}
        ]
      )

    names = context |> DynamicTool.Context.tool_specs() |> Enum.map(&Map.fetch!(&1, "name"))

    assert Enum.sort(names) ==
             Enum.sort([
               "workflow_plan_snapshot",
               "workflow_plan_upsert",
               "workflow_plan_update_item",
               "workflow_plan_render_workpad",
               "linear_plan_snapshot",
               "linear_plan_upsert",
               "linear_plan_update_item",
               "linear_plan_render_workpad"
             ])

    refute "repo_commit" in names
    refute "linear_move_issue" in names
    refute "tapd_move_issue" in names

    assert {:ok, [%{capability: "workflow.plan_snapshot", tool: "workflow_plan_snapshot"}]} =
             Inventory.resolve_required(context, [CapabilityNames.workflow_plan_snapshot()])

    assert {:success, %{"data" => %{"plan" => %{"plan_id" => @plan_id}}}} =
             DynamicTool.execute(context, "workflow_plan_snapshot", %{"plan_id" => @plan_id})
  end

  defp plan(items) do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => @plan_id,
      "run_id" => @run_id,
      "issue_id" => @issue_id,
      "tracker_kind" => "linear",
      "workflow_profile" => @profile,
      "route_key" => "developing",
      "status" => "active",
      "items" => items,
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp workflow_settings(tracker_kind, enabled? \\ true) do
    %{
      workflow: %{
        profile: %{
          kind: "coding_pr_delivery",
          version: 1,
          options: %{
            "structured_execution_plan" => %{"enabled" => enabled?}
          }
        }
      },
      tracker: %{kind: tracker_kind}
    }
  end

  defp backend_item(item_id, opts \\ []) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => "tool_evidence",
      "status" => "pending",
      "required" => true,
      "criticality" => "handoff_blocking",
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "repo_commit",
          "required_fields" => ["head_sha"],
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => Keyword.get(opts, :evidence_refs, []),
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp agent_item(item_id) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => "agent_step",
      "status" => "pending",
      "required" => false,
      "criticality" => "informational",
      "owned_by" => "agent",
      "source" => "agent",
      "depends_on" => [],
      "evidence_requirements" => [],
      "evidence_refs" => [],
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp evidence_ref(evidence_kind, payload) do
    %{
      "evidence_id" => "evidence-test-#{evidence_kind}",
      "evidence_kind" => evidence_kind,
      "source" => "tool_generated",
      "producer" => evidence_kind,
      "run_id" => @run_id,
      "issue_id" => @issue_id,
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => payload
    }
  end
end
