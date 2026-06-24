defmodule SymphonyElixir.Agent.ExecutionPlan.SQLiteStorageContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.Contract, as: AgentSQLiteContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.Contract, as: WorkflowSQLiteContract

  @runtime_files [
    "lib/symphony_elixir/agent/execution_plan/storage/sqlite/plan_record.ex",
    "lib/symphony_elixir/agent/execution_plan/storage/sqlite_backend.ex",
    "lib/symphony_elixir/workflow/structured_execution_plan/storage/sqlite/envelope_record.ex",
    "lib/symphony_elixir/workflow/structured_execution_plan/storage/sqlite_backend.ex"
  ]

  test "runtime SQLite storage modules read table names through storage contracts" do
    table_names = [AgentSQLiteContract.table_name(), WorkflowSQLiteContract.table_name()]

    offenders =
      for file <- @runtime_files,
          table_name <- table_names,
          source = File.read!(file),
          String.contains?(source, inspect(table_name)) do
        {file, table_name}
      end

    assert offenders == [],
           "runtime SQLite storage modules must use SQLite storage contracts for table names; offenders:\n#{format_offenders(offenders)}"
  end

  test "SQLite storage contracts expose the current physical tables" do
    assert AgentSQLiteContract.table() == :agent_execution_plans
    assert AgentSQLiteContract.table_name() == "agent_execution_plans"

    assert WorkflowSQLiteContract.table() == :workflow_execution_plan_envelopes
    assert WorkflowSQLiteContract.table_name() == "workflow_execution_plan_envelopes"
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", fn {file, table_name} -> "- #{file}: #{inspect(table_name)}" end)
  end
end
