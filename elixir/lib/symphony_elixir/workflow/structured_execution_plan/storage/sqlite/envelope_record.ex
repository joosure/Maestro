defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.EnvelopeRecord do
  @moduledoc false

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.Contract

  use Ecto.Schema

  @table_name Contract.table_name()
  @plan_id_column Contract.column!(:plan_id)
  @schema_id_column Contract.column!(:schema_id)
  @status_column Contract.column!(:status)
  @revision_column Contract.column!(:revision)
  @run_id_column Contract.column!(:run_id)
  @issue_id_column Contract.column!(:issue_id)
  @issue_identifier_column Contract.column!(:issue_identifier)
  @tracker_kind_column Contract.column!(:tracker_kind)
  @workflow_profile_kind_column Contract.column!(:workflow_profile_kind)
  @workflow_profile_version_column Contract.column!(:workflow_profile_version)
  @route_key_column Contract.column!(:route_key)
  @active_key_column Contract.column!(:active_key)
  @envelope_column Contract.column!(:envelope)

  @primary_key {@plan_id_column, :string, []}
  schema @table_name do
    field(@schema_id_column, :string)
    field(@status_column, :string)
    field(@revision_column, :integer)
    field(@run_id_column, :string)
    field(@issue_id_column, :string)
    field(@issue_identifier_column, :string)
    field(@tracker_kind_column, :string)
    field(@workflow_profile_kind_column, :string)
    field(@workflow_profile_version_column, :integer)
    field(@route_key_column, :string)
    field(@active_key_column, :string)
    field(@envelope_column, :map)

    timestamps(type: :utc_datetime_usec)
  end
end
