defmodule SymphonyElixir.Workflow.Extension.StateStore.MemoryBackend do
  @moduledoc """
  In-memory workflow extension state backend for non-durable runtime profiles.

  This backend exists for tests and explicit `:memory` storage mode. Production
  durable profiles should use the SQLite adapter selected by platform storage.
  """

  @behaviour SymphonyElixir.Workflow.Extension.StateStore

  alias SymphonyElixir.Workflow.Extension.StateStore.Record, as: StateStoreRecord

  @table __MODULE__

  @impl true
  def put(%StateStoreRecord{} = record, _opts) do
    ensure_table!()
    :ets.insert(@table, {record.id, record})
    {:ok, record}
  end

  @impl true
  def get(extension_id, workflow_scope, state_type, state_key, opts) do
    with {:ok, identity_record} <- StateStoreRecord.new(identity_attrs(extension_id, workflow_scope, state_type, state_key)) do
      ensure_table!()
      scope_key = identity_record.workflow_scope_key
      id = identity_record.id
      now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.system_time(:millisecond) end)
      include_expired? = Keyword.get(opts, :include_expired?, false)

      record =
        case :ets.lookup(@table, id) do
          [{^id, %StateStoreRecord{workflow_scope_key: ^scope_key} = record}] ->
            if include_expired? or not StateStoreRecord.stale?(record, now_ms), do: record

          _other ->
            nil
        end

      {:ok, record}
    end
  end

  @impl true
  def list(extension_id, workflow_scope, state_type, opts) do
    with {:ok, scope_key} <- StateStoreRecord.scope_key(workflow_scope) do
      ensure_table!()
      now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.system_time(:millisecond) end)
      include_expired? = Keyword.get(opts, :include_expired?, false)
      limit = Keyword.get(opts, :limit)

      records =
        @table
        |> :ets.tab2list()
        |> Enum.map(fn {_id, record} -> record end)
        |> Enum.filter(fn %StateStoreRecord{} = record ->
          record.extension_id == extension_id and
            record.workflow_scope_key == scope_key and
            record.state_type == state_type and
            (include_expired? or not StateStoreRecord.stale?(record, now_ms))
        end)
        |> Enum.sort_by(& &1.state_key)
        |> maybe_take(limit)

      {:ok, records}
    end
  end

  @impl true
  def delete(extension_id, workflow_scope, state_type, state_key, _opts) do
    with {:ok, identity_record} <- StateStoreRecord.new(identity_attrs(extension_id, workflow_scope, state_type, state_key)) do
      ensure_table!()
      :ets.delete(@table, identity_record.id)
      :ok
    end
  end

  @spec reset(keyword()) :: :ok
  def reset(_opts) do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp identity_attrs(extension_id, workflow_scope, state_type, state_key) do
    %{
      extension_id: extension_id,
      workflow_scope: workflow_scope,
      state_type: state_type,
      state_key: state_key,
      payload: %{}
    }
  end

  defp maybe_take(records, limit) when is_integer(limit) and limit >= 0, do: Enum.take(records, limit)
  defp maybe_take(records, _limit), do: records

  defp ensure_table! do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
      rescue
        ArgumentError -> @table
      end
    end
  end
end
