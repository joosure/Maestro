defmodule SymphonyElixir.Storage.Repo.Migrations.CreateExecutionPlanStorage do
  use Ecto.Migration

  @agent_plan_table :agent_execution_plans
  @workflow_envelope_table :workflow_execution_plan_envelopes
  @active_key_present_where "active_key IS NOT NULL"

  def change do
    create table(@agent_plan_table, primary_key: false) do
      add(:plan_id, :text, primary_key: true)
      add(:schema_id, :text, null: false)
      add(:status, :text, null: false)
      add(:revision, :integer, null: false)
      add(:context_kind, :text)
      add(:workspace_id, :text)
      add(:run_id, :text)
      add(:source, :text)
      add(:mode, :text)
      add(:payload, :map, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(@agent_plan_table, [:status]))
    create(index(@agent_plan_table, [:run_id]))
    create(index(@agent_plan_table, [:workspace_id]))

    create table(@workflow_envelope_table, primary_key: false) do
      add(:plan_id, :text, primary_key: true)
      add(:schema_id, :text, null: false)
      add(:status, :text, null: false)
      add(:revision, :integer)
      add(:run_id, :text, null: false)
      add(:issue_id, :text, null: false)
      add(:issue_identifier, :text)
      add(:tracker_kind, :text, null: false)
      add(:workflow_profile_kind, :text, null: false)
      add(:workflow_profile_version, :integer, null: false)
      add(:route_key, :text, null: false)
      add(:active_key, :text)
      add(:envelope, :map, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(@workflow_envelope_table, [:run_id]))
    create(index(@workflow_envelope_table, [:issue_id]))
    create(index(@workflow_envelope_table, [:tracker_kind]))
    create(index(@workflow_envelope_table, [:workflow_profile_kind, :workflow_profile_version, :route_key]))
    create(unique_index(@workflow_envelope_table, [:active_key], where: @active_key_present_where))
  end
end
