defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.StoreTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.StatusMachine, as: StatusMachineErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Store, as: AgentStore
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Renderer

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "rejects unsupported workflow storage backend override" do
    previous_flag = Process.flag(:trap_exit, true)

    try do
      assert {:error, {%ArgumentError{message: message}, _stack}} = Store.start_link(name: nil, workflow_storage_backend: :unknown)
      assert message =~ "unsupported Workflow structured execution-plan storage backend"
    after
      Process.flag(:trap_exit, previous_flag)
    end
  end

  test "creates and fetches one active plan per run profile route", %{store: store} do
    plan = minimal_plan()

    assert {:ok, ^plan} = Store.create(plan, server: store)
    assert {:ok, ^plan} = Store.fetch("plan-test-1", server: store)
    assert {:ok, ^plan} = Store.active_plan("run-test-1", %{"kind" => "coding_pr_delivery", "version" => 1}, "developing", server: store)
  end

  test "delegates generic persistence through Agent execution plan projection" do
    agent_store = start_supervised!(Supervisor.child_spec({AgentStore, name: nil}, id: :workflow_projection_agent_store))
    store = start_supervised!(Supervisor.child_spec({Store, name: nil, agent_store: agent_store}, id: :workflow_projection_store))

    plan = minimal_plan()

    assert {:ok, ^plan} = Store.create(plan, server: store)

    assert {:ok, agent_plan} = AgentStore.fetch("plan-test-1", server: agent_store)
    assert agent_plan["schema"] == "agent.execution_plan.v1"
    refute Map.has_key?(agent_plan, "issue_id")
    refute Map.has_key?(agent_plan, "tracker_kind")
    refute Map.has_key?(agent_plan, "workflow_profile")
    refute Map.has_key?(agent_plan, "route_key")
    assert [%{"source" => "agent_draft"}] = agent_plan["items"]

    assert {:ok, ^plan} = Store.fetch("plan-test-1", server: store)
  end

  test "reset deletes only workflow-owned Agent projections" do
    agent_store = start_supervised!(Supervisor.child_spec({AgentStore, name: nil}, id: :workflow_reset_agent_store))
    store = start_supervised!(Supervisor.child_spec({Store, name: nil, agent_store: agent_store}, id: :workflow_reset_store))

    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)
    assert {:ok, unrelated_agent_plan} = AgentStore.create(agent_plan("agent-only-plan"), server: agent_store)

    assert :ok = Store.reset(server: store)

    assert {:error, %{code: "plan_not_found"}} = Store.fetch("plan-test-1", server: store)
    assert {:error, %{code: "plan_not_found"}} = AgentStore.fetch("plan-test-1", server: agent_store)
    assert {:ok, ^unrelated_agent_plan} = AgentStore.fetch("agent-only-plan", server: agent_store)
  end

  test "active plan lookup rejects route keys outside the workflow profile", %{store: store} do
    assert {:error, %{code: "invalid_route_ref"}} =
             Store.active_plan("run-test-1", %{"kind" => "requirement_analysis", "version" => 1}, "developing", server: store)
  end

  test "duplicate active plan handling is deterministic", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan("plan-test-1"), server: store)

    assert {:error, %{code: "plan_conflict", active_plan_id: "plan-test-1"}} =
             Store.create(minimal_plan("plan-test-2"), server: store)
  end

  test "revision conflict returns a stable error", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    assert {:error, %{code: "revision_conflict", current_revision: 1, expected_revision: 0}} =
             Store.update_item_status("plan-test-1", "agent.plan", "in_progress", 0, server: store)
  end

  test "forbidden item status transitions are rejected", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    assert {:error, %{code: code}} =
             Store.update_item_status("plan-test-1", "agent.plan", "failed", 1, server: store)

    assert code == StatusMachineErrorCodes.item_status_transition_forbidden()
  end

  test "closed plans reject item updates", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)
    assert {:ok, %{"revision" => 2, "status" => "closed"}} = Store.update_plan_status("plan-test-1", "closed", 1, server: store)

    assert {:error, %{code: "item_update_not_allowed", status: "closed"}} =
             Store.update_item_status("plan-test-1", "agent.plan", "in_progress", 2, server: store)
  end

  test "superseded plans reject item updates", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    assert {:ok, %{"revision" => 2, "status" => "superseded"}} =
             Store.update_plan_status("plan-test-1", "superseded", 1, server: store)

    assert {:error, %{code: "item_update_not_allowed", status: "superseded"}} =
             Store.update_item_status("plan-test-1", "agent.plan", "in_progress", 2, server: store)
  end

  test "evidence refs are append-only and immutable", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    assert {:ok, %{"revision" => 2, "items" => [%{"evidence_refs" => [ref]}]}} =
             Store.append_evidence_ref("plan-test-1", "agent.plan", evidence_ref(), 1, server: store)

    assert ref == evidence_ref()

    assert {:ok, %{"revision" => 2, "items" => [%{"evidence_refs" => [^ref]}]}} =
             Store.append_evidence_ref("plan-test-1", "agent.plan", evidence_ref(), 2, server: store)

    changed_ref = put_in(evidence_ref(), ["payload", "head_sha"], "def456")

    assert {:error, %{code: "evidence_ref_conflict", evidence_id: "evidence-test-1"}} =
             Store.append_evidence_ref("plan-test-1", "agent.plan", changed_ref, 2, server: store)
  end

  test "render markers are stored without changing canonical plan revision", %{store: store} do
    plan = minimal_plan()

    assert {:ok, ^plan} = Store.create(plan, server: store)
    assert {:ok, %{"marker" => marker}} = Renderer.render(plan)

    assert {:ok, %{"revision" => 1, "rendering" => ^marker}} =
             Store.record_render_marker("plan-test-1", marker, 1, server: store)

    stale_marker = Map.put(marker, "plan_revision", 2)

    assert {:error, %{code: "rendering_failed"}} =
             Store.record_render_marker("plan-test-1", stale_marker, 1, server: store)
  end

  defp minimal_plan(plan_id \\ "plan-test-1") do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => plan_id,
      "run_id" => "run-test-1",
      "issue_id" => "TES-79",
      "tracker_kind" => "linear",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "route_key" => "developing",
      "status" => "active",
      "items" => [minimal_item()],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp minimal_item do
    %{
      "item_id" => "agent.plan",
      "parent_item_id" => nil,
      "title" => "Track implementation progress",
      "kind" => "agent_step",
      "status" => "pending",
      "required" => false,
      "criticality" => "informational",
      "owned_by" => "agent",
      "source" => "agent",
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
      "evidence_id" => "evidence-test-1",
      "evidence_kind" => "repo_push",
      "source" => "tool_generated",
      "producer" => "repo_push",
      "run_id" => "run-test-1",
      "issue_id" => "TES-79",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => %{"branch" => "feature/demo", "head_sha" => "abc123"}
    }
  end

  defp agent_plan(plan_id) do
    %{
      "schema" => "agent.execution_plan.v1",
      "plan_id" => plan_id,
      "context" => %{
        "context_kind" => "agent_run",
        "workspace_id" => "workspace-1",
        "run_id" => "run-agent-1",
        "source" => "agent",
        "mode" => "execution"
      },
      "status" => "active",
      "items" => [],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end
end
