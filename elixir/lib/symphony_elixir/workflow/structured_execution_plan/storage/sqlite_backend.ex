defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLiteBackend do
  @moduledoc """
  SQLite-backed durable storage for workflow execution-plan envelopes.

  This backend persists workflow adoption metadata only. Generic plan payloads
  are persisted by the Agent execution-plan SQLite backend.
  """

  @behaviour SymphonyElixir.Workflow.StructuredExecutionPlan.Storage

  import Ecto.Query

  alias SymphonyElixir.Storage.ErrorCodes, as: StorageErrorCodes
  alias SymphonyElixir.Storage.Repo
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.ActiveKey
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.Contract, as: SQLiteContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.EnvelopeRecord

  @plan_id_column SQLiteContract.column!(:plan_id)
  @schema_id_column SQLiteContract.column!(:schema_id)
  @status_column SQLiteContract.column!(:status)
  @revision_column SQLiteContract.column!(:revision)
  @run_id_column SQLiteContract.column!(:run_id)
  @issue_id_column SQLiteContract.column!(:issue_id)
  @issue_identifier_column SQLiteContract.column!(:issue_identifier)
  @tracker_kind_column SQLiteContract.column!(:tracker_kind)
  @workflow_profile_kind_column SQLiteContract.column!(:workflow_profile_kind)
  @workflow_profile_version_column SQLiteContract.column!(:workflow_profile_version)
  @route_key_column SQLiteContract.column!(:route_key)
  @active_key_column SQLiteContract.column!(:active_key)
  @envelope_column SQLiteContract.column!(:envelope)
  @inserted_at_column SQLiteContract.column!(:inserted_at)
  @updated_at_column SQLiteContract.column!(:updated_at)
  @upsert_replace_columns SQLiteContract.upsert_replace_columns()

  defstruct repo: Repo

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{repo: Keyword.get(opts, :repo, Repo)}}
  end

  @impl true
  def fetch_envelope(%__MODULE__{repo: repo}, plan_id) do
    case repo.get(EnvelopeRecord, plan_id) do
      nil -> :error
      %EnvelopeRecord{envelope: envelope} -> {:ok, envelope}
    end
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def put_envelope(%__MODULE__{repo: repo} = state, envelope) do
    row = row_from_envelope(envelope)

    repo.insert_all(
      EnvelopeRecord,
      [row],
      on_conflict: {:replace, @upsert_replace_columns},
      conflict_target: [@plan_id_column]
    )

    {:ok, state}
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def delete_envelope(%__MODULE__{repo: repo} = state, plan_id) do
    repo.delete_all(from(record in EnvelopeRecord, where: field(record, ^@plan_id_column) == ^plan_id))
    {:ok, state}
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def active_plan_id(%__MODULE__{repo: repo}, key) do
    active_key = ActiveKey.encode(key)

    query =
      from(record in EnvelopeRecord,
        where: field(record, ^@active_key_column) == ^active_key,
        select: field(record, ^@plan_id_column),
        limit: 1
      )

    case repo.one(query) do
      nil -> :error
      plan_id -> {:ok, plan_id}
    end
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def list_plan_ids(%__MODULE__{repo: repo}) do
    {:ok, repo.all(from(record in EnvelopeRecord, select: field(record, ^@plan_id_column)))}
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def reset(%__MODULE__{repo: repo} = state) do
    repo.delete_all(EnvelopeRecord)
    {:ok, state}
  rescue
    error -> {:error, storage_error(error)}
  end

  defp row_from_envelope(envelope) do
    now = DateTime.utc_now(:microsecond)
    workflow_profile = Map.fetch!(envelope, Fields.workflow_profile())

    %{
      @plan_id_column => Map.fetch!(envelope, Fields.plan_id()),
      @schema_id_column => Map.fetch!(envelope, Fields.schema()),
      @status_column => Map.fetch!(envelope, Fields.status()),
      @revision_column => Map.get(envelope, Fields.revision()),
      @run_id_column => Map.fetch!(envelope, Fields.run_id()),
      @issue_id_column => Map.fetch!(envelope, Fields.issue_id()),
      @issue_identifier_column => Map.get(envelope, Fields.issue_identifier()),
      @tracker_kind_column => Map.fetch!(envelope, Fields.tracker_kind()),
      @workflow_profile_kind_column => Map.fetch!(workflow_profile, Fields.profile_kind()),
      @workflow_profile_version_column => Map.fetch!(workflow_profile, Fields.profile_version()),
      @route_key_column => Map.fetch!(envelope, Fields.route_key()),
      @active_key_column => active_key_from_envelope(envelope),
      @envelope_column => envelope,
      @inserted_at_column => now,
      @updated_at_column => now
    }
  end

  defp active_key_from_envelope(envelope) do
    if ActiveKey.active?(envelope) do
      envelope
      |> ActiveKey.from_envelope!()
      |> ActiveKey.encode()
    end
  end

  defp storage_error(error) do
    %{
      code: StorageErrorCodes.storage_error(),
      message: "Workflow execution plan storage operation failed.",
      error: Exception.message(error)
    }
  end
end
