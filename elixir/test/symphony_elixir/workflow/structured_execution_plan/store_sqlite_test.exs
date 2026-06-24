defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.StoreSQLiteTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLiteBackend, as: AgentSQLiteBackend
  alias SymphonyElixir.Agent.ExecutionPlan.Store, as: AgentStore
  alias SymphonyElixir.Storage.{Migrator, Repo}
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLiteBackend, as: WorkflowSQLiteBackend
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  setup do
    root = Path.join(System.tmp_dir!(), "symphony-workflow-execution-plan-sqlite-#{System.unique_integer([:positive])}")
    db_path = Path.join(root, "plans.db")

    start_supervised!({Repo, database: db_path, pool_size: 1, journal_mode: :wal, busy_timeout: 5_000})
    assert :ok = Migrator.migrate(Repo)

    on_exit(fn -> File.rm_rf(root) end)

    {:ok, repo: Repo}
  end

  test "persists workflow envelopes and active index across Store restarts", %{repo: repo} do
    {:ok, agent_store} = AgentStore.start_link(name: nil, backend: AgentSQLiteBackend, repo: repo)

    {:ok, store} =
      Store.start_link(
        name: nil,
        agent_store: agent_store,
        backend: AgentSQLiteBackend,
        workflow_storage_backend: WorkflowSQLiteBackend,
        repo: repo
      )

    plan = minimal_plan()

    assert {:ok, ^plan} = Store.create(plan, server: store)

    assert :ok = GenServer.stop(store)
    assert :ok = GenServer.stop(agent_store)

    {:ok, restarted_agent_store} = AgentStore.start_link(name: nil, backend: AgentSQLiteBackend, repo: repo)

    {:ok, restarted_store} =
      Store.start_link(
        name: nil,
        agent_store: restarted_agent_store,
        backend: AgentSQLiteBackend,
        workflow_storage_backend: WorkflowSQLiteBackend,
        repo: repo
      )

    assert {:ok, ^plan} = Store.fetch("plan-workflow-sqlite-1", server: restarted_store)

    assert {:ok, ^plan} =
             Store.active_plan(
               "run-workflow-sqlite-1",
               %{"kind" => "coding_pr_delivery", "version" => 1},
               "developing",
               server: restarted_store
             )
  end

  defp minimal_plan do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => "plan-workflow-sqlite-1",
      "run_id" => "run-workflow-sqlite-1",
      "issue_id" => "TES-SQLITE-1",
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
end
