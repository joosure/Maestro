defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutorTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.Workflow.CapabilityNames
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
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

  test "provider-facing aliases preserve canonical workflow capability ids", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    alias_spec = ToolExecutor.tool_specs(provider_aliases: ["linear"]) |> Enum.find(&(&1["name"] == "linear_plan_update_item"))
    render_alias_spec = ToolExecutor.tool_specs(provider_aliases: ["linear"]) |> Enum.find(&(&1["name"] == "linear_plan_render_workpad"))

    assert alias_spec["workflowCapability"] == CapabilityNames.workflow_plan_update_item()
    assert render_alias_spec["workflowCapability"] == CapabilityNames.workflow_plan_render_workpad()

    assert {:success, %{"data" => %{"changed_items" => [%{"item_id" => "agent.plan", "status" => "in_progress"}]}}} =
             ToolExecutor.execute(
               "linear_plan_update_item",
               %{"plan_id" => @plan_id, "item_id" => "agent.plan", "status" => "in_progress", "plan_revision" => 1},
               server: store
             )

    assert {:success, %{"data" => %{"rendered_workpad" => %{"mode" => "preview"}}}} =
             ToolExecutor.execute(
               "linear_plan_render_workpad",
               %{"plan_id" => @plan_id, "plan_revision" => 2, "mode" => "preview"},
               server: store
             )
  end

  test "explicit planning-only source exposes plan tools without repo or tracker mutation", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([agent_item("agent.plan")]), server: store)

    context =
      DynamicTool.capture_context(
        dynamic_tool_sources: [
          {DynamicToolSource, %{server: store}}
        ]
      )

    names = Enum.map(context.tool_specs, &Map.fetch!(&1, "name"))

    assert Enum.sort(names) ==
             Enum.sort([
               "workflow_plan_snapshot",
               "workflow_plan_upsert",
               "workflow_plan_update_item",
               "workflow_plan_render_workpad"
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
