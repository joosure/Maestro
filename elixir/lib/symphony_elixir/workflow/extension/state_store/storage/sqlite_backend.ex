defmodule SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLiteBackend do
  @moduledoc """
  SQLite-backed storage adapter for workflow extension-owned state.

  The adapter maps the stable `Extension.StateStore.Record` envelope to SQLite. It does
  not interpret extension payload semantics.
  """

  @behaviour SymphonyElixir.Workflow.Extension.StateStore

  import Ecto.Query

  alias SymphonyElixir.Storage.Repo
  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.StateStore.Record, as: StateStoreRecord
  alias SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Contract
  alias SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Record

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
  @inserted_at_column Contract.column!(:inserted_at)
  @updated_at_column Contract.column!(:updated_at)
  @upsert_replace_columns Contract.upsert_replace_columns()

  @impl true
  def put(%StateStoreRecord{} = record, opts) do
    repo = Keyword.get(opts, :repo, Repo)
    now = DateTime.utc_now(:microsecond)
    persisted_record = %{record | inserted_at: record.inserted_at || now, updated_at: now}
    row = row_from_record(persisted_record)

    repo.insert_all(
      Record,
      [row],
      on_conflict: {:replace, @upsert_replace_columns},
      conflict_target: [@extension_id_column, @workflow_scope_key_column, @state_type_column, @state_key_column]
    )

    case get(record.extension_id, record.workflow_scope, record.state_type, record.state_key,
           repo: repo,
           include_expired?: true
         ) do
      {:ok, %StateStoreRecord{} = persisted_record} ->
        {:ok, persisted_record}

      {:ok, nil} ->
        {:error, storage_error(:upserted_record_not_found)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def get(extension_id, workflow_scope, state_type, state_key, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, scope_key} <- StateStoreRecord.scope_key(workflow_scope) do
      now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.system_time(:millisecond) end)
      include_expired? = Keyword.get(opts, :include_expired?, false)

      query =
        Record
        |> by_identity(extension_id, scope_key, state_type)
        |> where([record], field(record, ^@state_key_column) == ^state_key)
        |> maybe_not_expired(include_expired?, now_ms)
        |> limit(1)

      {:ok, record_from_schema(repo.one(query))}
    end
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def list(extension_id, workflow_scope, state_type, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, scope_key} <- StateStoreRecord.scope_key(workflow_scope) do
      now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.system_time(:millisecond) end)
      include_expired? = Keyword.get(opts, :include_expired?, false)
      limit_count = Keyword.get(opts, :limit)

      records =
        Record
        |> by_identity(extension_id, scope_key, state_type)
        |> maybe_not_expired(include_expired?, now_ms)
        |> order_by([record], asc: field(record, ^@state_key_column))
        |> maybe_limit(limit_count)
        |> repo.all()
        |> Enum.map(&record_from_schema/1)

      {:ok, records}
    end
  rescue
    error -> {:error, storage_error(error)}
  end

  @impl true
  def delete(extension_id, workflow_scope, state_type, state_key, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, scope_key} <- StateStoreRecord.scope_key(workflow_scope) do
      Record
      |> by_identity(extension_id, scope_key, state_type)
      |> where([record], field(record, ^@state_key_column) == ^state_key)
      |> repo.delete_all()

      :ok
    end
  rescue
    error -> {:error, storage_error(error)}
  end

  @spec reset(keyword()) :: :ok | {:error, map()}
  def reset(opts) do
    opts
    |> Keyword.get(:repo, Repo)
    |> then(& &1.delete_all(Record))

    :ok
  rescue
    error -> {:error, storage_error(error)}
  end

  defp by_identity(queryable, extension_id, scope_key, state_type) do
    from(record in queryable,
      where:
        field(record, ^@extension_id_column) == ^extension_id and
          field(record, ^@workflow_scope_key_column) == ^scope_key and
          field(record, ^@state_type_column) == ^state_type
    )
  end

  defp maybe_not_expired(query, true, _now_ms), do: query

  defp maybe_not_expired(query, false, now_ms) do
    from(record in query,
      where: is_nil(field(record, ^@expires_at_ms_column)) or field(record, ^@expires_at_ms_column) > ^now_ms
    )
  end

  defp maybe_limit(query, limit_count) when is_integer(limit_count) and limit_count >= 0 do
    limit(query, ^limit_count)
  end

  defp maybe_limit(query, _limit_count), do: query

  defp row_from_record(%StateStoreRecord{} = record) do
    %{
      @id_column => record.id,
      @extension_id_column => record.extension_id,
      @extension_version_column => record.extension_version,
      @workflow_scope_key_column => record.workflow_scope_key,
      @workflow_scope_column => record.workflow_scope,
      @state_type_column => record.state_type,
      @state_key_column => record.state_key,
      @payload_schema_column => record.payload_schema,
      @payload_json_column => record.payload,
      @expires_at_ms_column => record.expires_at_ms,
      @inserted_at_column => record.inserted_at,
      @updated_at_column => record.updated_at
    }
  end

  defp record_from_schema(nil), do: nil

  defp record_from_schema(%Record{} = schema) do
    StateStoreRecord.new!(%{
      id: Map.fetch!(schema, @id_column),
      extension_id: Map.fetch!(schema, @extension_id_column),
      extension_version: Map.get(schema, @extension_version_column),
      workflow_scope_key: Map.fetch!(schema, @workflow_scope_key_column),
      workflow_scope: Map.fetch!(schema, @workflow_scope_column),
      state_type: Map.fetch!(schema, @state_type_column),
      state_key: Map.fetch!(schema, @state_key_column),
      payload_schema: Map.get(schema, @payload_schema_column),
      payload: Map.fetch!(schema, @payload_json_column),
      expires_at_ms: Map.get(schema, @expires_at_ms_column),
      inserted_at: Map.get(schema, @inserted_at_column),
      updated_at: Map.get(schema, @updated_at_column)
    })
  end

  defp storage_error(error) do
    %{
      code: ErrorCodes.state_store_error(),
      message: "Workflow extension state store operation failed.",
      error: error_diagnostic(error)
    }
  end

  defp error_diagnostic(reason) when is_atom(reason) and not is_nil(reason), do: reason
  defp error_diagnostic(%_{} = error), do: Diagnostics.exception(error)
  defp error_diagnostic(error), do: %{type: Diagnostics.type_name(error)}
end
