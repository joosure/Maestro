defmodule SymphonyElixir.Agent.ExecutionPlan.ToolExecutorTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.ExecutionPlan.DynamicToolSource
  alias SymphonyElixir.Agent.ExecutionPlan.Store
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Arguments, as: ToolArguments

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Command.{
    AppendEvidenceRef,
    Create,
    MergeItems
  }

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Contract, as: ToolContract
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Options, as: ToolOptions
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Payload, as: ToolPayload
  alias SymphonyElixir.Agent.ExecutionPlan.ToolExecutor

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "agent execution plan tool specs use stable capability metadata" do
    specs = ToolExecutor.tool_specs()
    names = Enum.map(specs, &Map.fetch!(&1, "name"))

    assert Enum.sort(names) == Enum.sort(ToolContract.tools())

    snapshot = Enum.find(specs, &(&1["name"] == ToolContract.snapshot_tool()))
    append_evidence = Enum.find(specs, &(&1["name"] == ToolContract.append_evidence_tool()))

    assert snapshot["capability"] == ToolContract.snapshot_capability()
    assert append_evidence["capability"] == ToolContract.append_evidence_capability()
    assert snapshot["sourceKind"] == "agent"
    assert snapshot["operatorOnly"] == true
  end

  test "tool options own store routing and clock option normalization", %{store: store} do
    opts = [agent_execution_plan_store: store, updated_at: "2026-05-20T00:00:01Z", expose?: true]

    assert ToolOptions.source_context(opts) == %{
             expose?: true,
             server: store,
             updated_at: "2026-05-20T00:00:01Z"
           }

    assert ToolOptions.store_opts(opts) == [updated_at: "2026-05-20T00:00:01Z", server: store]

    assert ToolOptions.merge_source_context([], %{"server" => store, "now" => "2026-05-20T00:00:02Z"}) == [
             now: "2026-05-20T00:00:02Z",
             server: store
           ]
  end

  test "tool arguments wrap complex payloads before executor orchestration" do
    assert {:ok, %Create{plan: %ToolPayload.Plan{} = plan_payload}} = ToolArguments.upsert(%{"plan" => minimal_plan()})
    assert ToolPayload.plan_map(plan_payload)["plan_id"] == "plan-agent-1"

    assert {:ok, %MergeItems{items: %ToolPayload.ItemSet{} = item_set}} =
             ToolArguments.upsert(%{"plan_id" => "plan-agent-1", "plan_revision" => 1, "items" => [agent_item("agent.follow_up")]})

    assert [%{"item_id" => "agent.follow_up"}] = ToolPayload.item_maps(item_set)

    assert {:ok, %AppendEvidenceRef{evidence_ref: %ToolPayload.EvidenceRef{} = evidence_ref_payload}} =
             ToolArguments.append_evidence(%{
               "plan_id" => "plan-agent-1",
               "item_id" => "agent.plan",
               "evidence_ref" => evidence_ref(),
               "plan_revision" => 1
             })

    assert ToolPayload.evidence_ref_map(evidence_ref_payload) == evidence_ref()
  end

  test "explicit source defaults to not exposing tools", %{store: store} do
    context =
      DynamicTool.capture_context(
        dynamic_tool_sources: [
          {DynamicToolSource, %{server: store}}
        ]
      )

    assert DynamicTool.Context.tool_specs(context) == []
  end

  test "explicit opt-in source exposes generic Agent plan tools", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    context =
      DynamicTool.capture_context(
        dynamic_tool_sources: [
          {DynamicToolSource, %{server: store, expose?: true}}
        ]
      )

    assert ToolContract.snapshot_tool() in (context |> DynamicTool.Context.tool_specs() |> Enum.map(&Map.fetch!(&1, "name")))

    assert {:success, %{"data" => %{"plan" => %{"plan_id" => "plan-agent-1", "item_count" => 1}}}} =
             DynamicTool.execute(context, ToolContract.snapshot_tool(), %{"plan_id" => "plan-agent-1"})
  end

  test "upsert creates and merges only generic Agent plans", %{store: store} do
    assert {:success, %{"data" => %{"plan" => %{"plan_id" => "plan-agent-1", "revision" => 1}}}} =
             ToolExecutor.execute(ToolContract.upsert_tool(), %{"plan" => minimal_plan()}, server: store)

    assert {:success,
            %{
              "data" => %{
                "plan" => %{"revision" => 2},
                "changed_items" => [%{"item_id" => "agent.follow_up", "source" => "agent_draft"}]
              }
            }} =
             ToolExecutor.execute(
               ToolContract.upsert_tool(),
               %{"plan_id" => "plan-agent-1", "plan_revision" => 1, "items" => [agent_item("agent.follow_up")]},
               server: store
             )
  end

  test "update item rejects non-agent-owned completion through the tool surface", %{store: store} do
    assert {:ok, _plan} = Store.create(policy_plan(), server: store)

    assert {:failure, %{"error" => %{"code" => "item_update_not_allowed", "details" => %{"item_id" => "policy.check"}}}} =
             ToolExecutor.execute(
               ToolContract.update_item_tool(),
               %{"plan_id" => "plan-agent-1", "item_id" => "policy.check", "status" => "complete", "plan_revision" => 1},
               server: store
             )
  end

  test "append evidence records immutable generic evidence refs", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    assert {:success,
            %{
              "data" => %{
                "plan" => %{"revision" => 2},
                "changed_items" => [%{"item_id" => "agent.plan", "evidence_ref_count" => 1}]
              }
            }} =
             ToolExecutor.execute(
               ToolContract.append_evidence_tool(),
               %{"plan_id" => "plan-agent-1", "item_id" => "agent.plan", "evidence_ref" => evidence_ref(), "plan_revision" => 1},
               server: store
             )
  end

  defp minimal_plan do
    %{
      "schema" => "agent.execution_plan.v1",
      "plan_id" => "plan-agent-1",
      "context" => %{
        "context_kind" => "agent_run",
        "workspace_id" => "workspace-1",
        "run_id" => "run-agent-1",
        "source" => "agent",
        "mode" => "execution"
      },
      "status" => "active",
      "items" => [agent_item("agent.plan")],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp policy_plan do
    minimal_plan()
    |> Map.put("items", [
      %{
        "item_id" => "policy.check",
        "title" => "Policy owned check",
        "kind" => "validation",
        "status" => "pending",
        "required" => true,
        "criticality" => "policy_required",
        "owned_by" => "policy",
        "source" => "policy_skeleton",
        "depends_on" => [],
        "evidence_requirements" => [
          %{
            "evidence_kind" => "validation_result",
            "required" => true,
            "required_fields" => ["ok"],
            "trust_classes" => ["tool_generated"]
          }
        ],
        "evidence_refs" => [],
        "created_at" => "2026-05-20T00:00:00Z",
        "updated_at" => "2026-05-20T00:00:00Z",
        "revision" => 1
      }
    ])
  end

  defp agent_item(item_id) do
    %{
      "item_id" => item_id,
      "title" => "Track execution progress",
      "kind" => "agent_step",
      "status" => "pending",
      "required" => false,
      "criticality" => "informational",
      "owned_by" => "agent",
      "source" => "agent_draft",
      "depends_on" => [],
      "evidence_requirements" => [],
      "evidence_refs" => [],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp evidence_ref do
    %{
      "evidence_id" => "evidence-agent-1",
      "evidence_kind" => "validation_result",
      "source" => "tool_generated",
      "producer" => "repo_diff",
      "run_id" => "run-agent-1",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => %{"head_sha" => "abc123"}
    }
  end
end
