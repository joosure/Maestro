defmodule SymphonyElixir.Storage.Repo.Migrations.CreateWorkflowExtensionStateRecords do
  use Ecto.Migration

  @table :workflow_extension_state_records

  def change do
    create table(@table, primary_key: false) do
      add(:id, :text, primary_key: true)
      add(:extension_id, :text, null: false)
      add(:extension_version, :text)
      add(:workflow_scope_key, :text, null: false)
      add(:workflow_scope, :map, null: false)
      add(:state_type, :text, null: false)
      add(:state_key, :text, null: false)
      add(:payload_schema, :text)
      add(:payload_json, :map, null: false)
      add(:expires_at_ms, :integer)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(@table, [:extension_id, :workflow_scope_key, :state_type, :state_key]))
    create(index(@table, [:extension_id]))
    create(index(@table, [:state_type]))
    create(index(@table, [:expires_at_ms]))
  end
end
