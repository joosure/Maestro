defmodule SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.PlanRecord do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.Contract

  use Ecto.Schema

  @table_name Contract.table_name()
  @plan_id_column Contract.column!(:plan_id)
  @schema_id_column Contract.column!(:schema_id)
  @status_column Contract.column!(:status)
  @revision_column Contract.column!(:revision)
  @context_kind_column Contract.column!(:context_kind)
  @workspace_id_column Contract.column!(:workspace_id)
  @run_id_column Contract.column!(:run_id)
  @source_column Contract.column!(:source)
  @mode_column Contract.column!(:mode)
  @payload_column Contract.column!(:payload)

  @primary_key {@plan_id_column, :string, []}
  @derive {Jason.Encoder, only: Contract.derive_fields()}
  schema @table_name do
    field(@schema_id_column, :string)
    field(@status_column, :string)
    field(@revision_column, :integer)
    field(@context_kind_column, :string)
    field(@workspace_id_column, :string)
    field(@run_id_column, :string)
    field(@source_column, :string)
    field(@mode_column, :string)
    field(@payload_column, :map)

    timestamps(type: :utc_datetime_usec)
  end
end
