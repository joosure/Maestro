defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.Contract do
  @moduledoc """
  SQLite storage identifiers for workflow execution-plan adoption envelopes.

  Workflow adoption persists only workflow-owned envelope metadata here. The
  generic Agent plan payload stays in Agent execution-plan storage.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: ExecutionPlanContract

  @table :workflow_execution_plan_envelopes
  @table_name Atom.to_string(@table)
  @owner :workflow_execution_plan_adoption
  @backend :sqlite
  @purpose "Workflow execution-plan adoption envelopes and active route/profile lookup metadata."

  @columns %{
    plan_id: :plan_id,
    schema_id: :schema_id,
    status: :status,
    revision: :revision,
    run_id: :run_id,
    issue_id: :issue_id,
    issue_identifier: :issue_identifier,
    tracker_kind: :tracker_kind,
    workflow_profile_kind: :workflow_profile_kind,
    workflow_profile_version: :workflow_profile_version,
    route_key: :route_key,
    active_key: :active_key,
    envelope: :envelope,
    inserted_at: :inserted_at,
    updated_at: :updated_at
  }

  @upsert_replace_columns [
    @columns.schema_id,
    @columns.status,
    @columns.revision,
    @columns.run_id,
    @columns.issue_id,
    @columns.issue_identifier,
    @columns.tracker_kind,
    @columns.workflow_profile_kind,
    @columns.workflow_profile_version,
    @columns.route_key,
    @columns.active_key,
    @columns.envelope,
    @columns.updated_at
  ]

  @spec table() :: atom()
  def table, do: @table

  @spec table_name() :: String.t()
  def table_name, do: @table_name

  @spec column!(atom()) :: atom()
  def column!(key), do: Map.fetch!(@columns, key)

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
