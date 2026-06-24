defmodule SymphonyElixir.Agent.ExecutionPlan.Storage.SQLiteBackend do
  @moduledoc """
  SQLite-backed durable storage for canonical Agent execution plans.

  The backend stores only `agent.execution_plan.v1` payloads. Workflow adoption
  metadata is persisted by the workflow storage backend.
  """

  @behaviour SymphonyElixir.Agent.ExecutionPlan.Storage

  import Ecto.Query

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.Contract, as: SQLiteContract
  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.PlanRecord
  alias SymphonyElixir.Storage.ErrorCodes, as: StorageErrorCodes
  alias SymphonyElixir.Storage.Repo

  @plan_id_column SQLiteContract.column!(:plan_id)
  @schema_id_column SQLiteContract.column!(:schema_id)
  @status_column SQLiteContract.column!(:status)
  @revision_column SQLiteContract.column!(:revision)
  @context_kind_column SQLiteContract.column!(:context_kind)
  @workspace_id_column SQLiteContract.column!(:workspace_id)
  @run_id_column SQLiteContract.column!(:run_id)
  @source_column SQLiteContract.column!(:source)
  @mode_column SQLiteContract.column!(:mode)
  @payload_column SQLiteContract.column!(:payload)
  @inserted_at_column SQLiteContract.column!(:inserted_at)
  @updated_at_column SQLiteContract.column!(:updated_at)
  @upsert_replace_columns SQLiteContract.upsert_replace_columns()

  defstruct repo: Repo

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{repo: Keyword.get(opts, :repo, Repo)}}
  end

  @impl true
  def fetch_plan(%__MODULE__{repo: repo}, plan_id) do
    case repo.get(PlanRecord, plan_id) do
      nil -> :error
      %PlanRecord{payload: payload} -> {:ok, payload}
    end
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def put_plan(%__MODULE__{repo: repo} = state, plan) do
    row = row_from_plan(plan)

    repo.insert_all(
      PlanRecord,
      [row],
      on_conflict: {:replace, @upsert_replace_columns},
      conflict_target: [@plan_id_column]
    )

    {:ok, state}
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def delete_plan(%__MODULE__{repo: repo} = state, plan_id) do
    repo.delete_all(from(record in PlanRecord, where: field(record, ^@plan_id_column) == ^plan_id))
    {:ok, state}
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def reset(%__MODULE__{repo: repo} = state) do
    repo.delete_all(PlanRecord)
    {:ok, state}
  rescue
    error -> {:error, storage_error(error)}
  end

  defp row_from_plan(plan) do
    now = DateTime.utc_now(:microsecond)
    context = Map.get(plan, Fields.context(), %{})

    %{
      @plan_id_column => Map.fetch!(plan, Fields.plan_id()),
      @schema_id_column => Map.fetch!(plan, Fields.schema()),
      @status_column => Map.fetch!(plan, Fields.status()),
      @revision_column => Map.fetch!(plan, Fields.revision()),
      @context_kind_column => Map.get(context, Fields.context_kind()),
      @workspace_id_column => Map.get(context, Fields.workspace_id()),
      @run_id_column => Map.get(context, Fields.run_id()),
      @source_column => Map.get(context, Fields.source()),
      @mode_column => Map.get(context, Fields.mode()),
      @payload_column => plan,
      @inserted_at_column => now,
      @updated_at_column => now
    }
  end

  defp storage_error(error) do
    %{
      code: StorageErrorCodes.storage_error(),
      message: "Agent execution plan storage operation failed.",
      error: Exception.message(error)
    }
  end
end
