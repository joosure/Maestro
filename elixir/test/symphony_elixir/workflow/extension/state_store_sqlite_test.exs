defmodule SymphonyElixir.Workflow.Extension.StateStoreSQLiteTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Storage.{Migrator, Repo}
  alias SymphonyElixir.Workflow.Extension.StateStore
  alias SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Contract
  alias SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLiteBackend

  setup do
    root = Path.join(System.tmp_dir!(), "symphony-workflow-extension-state-sqlite-#{System.unique_integer([:positive])}")
    db_path = Path.join(root, "extension-state.db")

    start_supervised!({Repo, database: db_path, pool_size: 1, journal_mode: :wal, busy_timeout: 5_000})
    assert :ok = Migrator.migrate(Repo)

    on_exit(fn -> File.rm_rf(root) end)

    {:ok, repo: Repo}
  end

  test "SQLite backend persists opaque workflow extension state records", %{repo: repo} do
    attrs = state_attrs("issue-sqlite-1")

    assert {:ok, record} = StateStore.put(attrs, backend: SQLiteBackend, repo: repo)

    assert {:ok, fetched} =
             StateStore.get(
               record.extension_id,
               record.workflow_scope,
               record.state_type,
               record.state_key,
               backend: SQLiteBackend,
               repo: repo
             )

    assert fetched == record

    updated_attrs = put_in(attrs[:payload]["url"], "https://example.test/pull/2")
    assert {:ok, updated} = StateStore.put(updated_attrs, backend: SQLiteBackend, repo: repo)
    assert updated.inserted_at == record.inserted_at
    assert DateTime.compare(updated.updated_at, record.updated_at) in [:gt, :eq]

    assert {:ok, [listed]} =
             StateStore.list(updated.extension_id, updated.workflow_scope, updated.state_type,
               backend: SQLiteBackend,
               repo: repo
             )

    assert listed.payload == %{"url" => "https://example.test/pull/2"}

    assert :ok =
             StateStore.delete(updated.extension_id, updated.workflow_scope, updated.state_type, updated.state_key,
               backend: SQLiteBackend,
               repo: repo
             )

    assert {:ok, nil} =
             StateStore.get(updated.extension_id, updated.workflow_scope, updated.state_type, updated.state_key,
               backend: SQLiteBackend,
               repo: repo
             )
  end

  test "SQLite contract exposes table-level catalog metadata only" do
    entry = Contract.catalog_entry()

    assert entry.owner == :workflow_extension_state
    assert entry.table == :workflow_extension_state_records
    assert entry.payload_schema == "workflow.extension_state_record.v1"
    refute Map.has_key?(entry, :columns)
  end

  defp state_attrs(issue_id) do
    %{
      extension_id: "symphony.workflow.extension.coding_pr_delivery",
      extension_version: "builtin",
      workflow_scope: %{
        "profile_kind" => "coding_pr_delivery",
        "profile_version" => 1,
        "route_key" => "developing"
      },
      state_type: "change_proposal.known_target.v1",
      state_key: issue_id,
      payload_schema: "change_proposal.known_target.v1",
      payload: %{"url" => "https://example.test/pull/1"}
    }
  end
end
