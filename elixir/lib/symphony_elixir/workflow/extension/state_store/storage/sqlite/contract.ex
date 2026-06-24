defmodule SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Contract do
  @moduledoc """
  SQLite storage identifiers for workflow extension-owned state envelopes.

  The contract names the physical table and columns for the SQLite adapter.
  Platform catalog entries remain table-level; payload semantics stay owned by
  each runtime extension.
  """

  alias SymphonyElixir.Workflow.Extension.StateStore.Record, as: StateStoreRecord

  @table :workflow_extension_state_records
  @table_name Atom.to_string(@table)
  @owner :workflow_extension_state
  @backend :sqlite
  @purpose "Opaque workflow runtime extension state envelopes."

  @columns %{
    id: :id,
    extension_id: :extension_id,
    extension_version: :extension_version,
    workflow_scope_key: :workflow_scope_key,
    workflow_scope: :workflow_scope,
    state_type: :state_type,
    state_key: :state_key,
    payload_schema: :payload_schema,
    payload_json: :payload_json,
    expires_at_ms: :expires_at_ms,
    inserted_at: :inserted_at,
    updated_at: :updated_at
  }

  @upsert_replace_columns [
    @columns.extension_version,
    @columns.workflow_scope,
    @columns.payload_schema,
    @columns.payload_json,
    @columns.expires_at_ms,
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
      payload_schema: StateStoreRecord.schema_id(),
      purpose: @purpose
    }
  end
end
