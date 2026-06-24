defmodule SymphonyElixir.Agent.ExecutionPlan.StoreSQLiteTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLiteBackend
  alias SymphonyElixir.Agent.ExecutionPlan.Store
  alias SymphonyElixir.Storage.{Migrator, Repo}

  setup do
    root = Path.join(System.tmp_dir!(), "symphony-agent-execution-plan-sqlite-#{System.unique_integer([:positive])}")
    db_path = Path.join(root, "plans.db")

    start_supervised!({Repo, database: db_path, pool_size: 1, journal_mode: :wal, busy_timeout: 5_000})
    assert :ok = Migrator.migrate(Repo)

    on_exit(fn -> File.rm_rf(root) end)

    {:ok, repo: Repo}
  end

  test "persists generic Agent execution plans across Store restarts", %{repo: repo} do
    {:ok, store} = Store.start_link(name: nil, backend: SQLiteBackend, repo: repo)

    assert {:ok, plan} = Store.create(minimal_plan(), server: store)
    assert :ok = GenServer.stop(store)

    {:ok, restarted_store} = Store.start_link(name: nil, backend: SQLiteBackend, repo: repo)

    assert {:ok, ^plan} = Store.fetch("plan-agent-sqlite-1", server: restarted_store)
  end

  defp minimal_plan do
    %{
      "schema" => "agent.execution_plan.v1",
      "plan_id" => "plan-agent-sqlite-1",
      "context" => %{
        "context_kind" => "agent_run",
        "workspace_id" => "workspace-sqlite-1",
        "run_id" => "run-agent-sqlite-1",
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
end
