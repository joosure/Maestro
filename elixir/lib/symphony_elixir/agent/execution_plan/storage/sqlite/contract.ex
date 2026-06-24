defmodule SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.Contract do
  @moduledoc """
  SQLite storage identifiers for canonical Agent execution-plan rows.

  These identifiers are the database boundary contract for the current SQLite
  backend. Runtime schema and backend code should read table and column names
  through this module instead of repeating physical storage literals.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: ExecutionPlanContract

  @table :agent_execution_plans
  @table_name Atom.to_string(@table)
  @owner :agent_execution_plan
  @backend :sqlite
  @purpose "Canonical Agent execution-plan payloads and bounded inspection projections."

  @columns %{
    plan_id: :plan_id,
    schema_id: :schema_id,
    status: :status,
    revision: :revision,
    context_kind: :context_kind,
    workspace_id: :workspace_id,
    run_id: :run_id,
    source: :source,
    mode: :mode,
    payload: :payload,
    inserted_at: :inserted_at,
    updated_at: :updated_at
  }

  @derive_fields [
    @columns.plan_id,
    @columns.schema_id,
    @columns.status,
    @columns.revision,
    @columns.context_kind,
    @columns.workspace_id,
    @columns.run_id,
    @columns.source,
    @columns.mode,
    @columns.payload,
    @columns.inserted_at,
    @columns.updated_at
  ]

  @upsert_replace_columns [
    @columns.schema_id,
    @columns.status,
    @columns.revision,
    @columns.context_kind,
    @columns.workspace_id,
    @columns.run_id,
    @columns.source,
    @columns.mode,
    @columns.payload,
    @columns.updated_at
  ]

  @spec table() :: atom()
  def table, do: @table

  @spec table_name() :: String.t()
  def table_name, do: @table_name

  @spec column!(atom()) :: atom()
  def column!(key), do: Map.fetch!(@columns, key)

  @spec derive_fields() :: [atom()]
  def derive_fields, do: @derive_fields

  @spec upsert_replace_columns() :: [atom()]
  def upsert_replace_columns, do: @upsert_replace_columns

  @spec catalog_entry() :: map()
  def catalog_entry do
    %{
      backend: @backend,
      owner: @owner,
      table: @table,
      table_name: @table_name,
      contract_module: __MODULE__,
      payload_schema: ExecutionPlanContract.schema_id(),
      purpose: @purpose
    }
  end
end
