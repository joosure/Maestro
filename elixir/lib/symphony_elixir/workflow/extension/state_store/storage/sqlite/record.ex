defmodule SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Record do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Contract

  use Ecto.Schema

  @table_name Contract.table_name()
  @id_column Contract.column!(:id)
  @extension_id_column Contract.column!(:extension_id)
  @extension_version_column Contract.column!(:extension_version)
  @workflow_scope_key_column Contract.column!(:workflow_scope_key)
  @workflow_scope_column Contract.column!(:workflow_scope)
  @state_type_column Contract.column!(:state_type)
  @state_key_column Contract.column!(:state_key)
  @payload_schema_column Contract.column!(:payload_schema)
  @payload_json_column Contract.column!(:payload_json)
  @expires_at_ms_column Contract.column!(:expires_at_ms)

  @primary_key {@id_column, :string, []}
  schema @table_name do
    field(@extension_id_column, :string)
    field(@extension_version_column, :string)
    field(@workflow_scope_key_column, :string)
    field(@workflow_scope_column, :map)
    field(@state_type_column, :string)
    field(@state_key_column, :string)
    field(@payload_schema_column, :string)
    field(@payload_json_column, :map)
    field(@expires_at_ms_column, :integer)

    timestamps(type: :utc_datetime_usec)
  end
end
