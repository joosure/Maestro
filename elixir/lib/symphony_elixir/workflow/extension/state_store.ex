defmodule SymphonyElixir.Workflow.Extension.StateStore do
  @moduledoc """
  Facade and behaviour for workflow extension-owned durable state.

  Extensions use this module as the stable state boundary. The selected backend
  owns physical persistence details; extension code must not depend on Repo,
  SQLite, SQL fragments, or database paths.
  """

  alias SymphonyElixir.Workflow.Extension.StateStore.BackendSelector
  alias SymphonyElixir.Workflow.Extension.StateStore.Options
  alias SymphonyElixir.Workflow.Extension.StateStore.Record, as: StateStoreRecord

  @callback put(StateStoreRecord.t(), keyword()) ::
              {:ok, StateStoreRecord.t()} | {:error, map()}

  @callback get(String.t(), map(), String.t(), String.t(), keyword()) ::
              {:ok, StateStoreRecord.t() | nil} | {:error, map()}

  @callback list(String.t(), map(), String.t(), keyword()) ::
              {:ok, [StateStoreRecord.t()]} | {:error, map()}

  @callback delete(String.t(), map(), String.t(), String.t(), keyword()) ::
              :ok | {:error, map()}

  @spec put(map() | StateStoreRecord.t(), keyword()) ::
          {:ok, StateStoreRecord.t()} | {:error, map()}
  def put(record_or_attrs, opts \\ [])

  def put(%StateStoreRecord{} = record, opts) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, backend} <- BackendSelector.select(opts) do
      backend.put(record, opts)
    end
  end

  def put(attrs, opts) when is_map(attrs) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, record} <- StateStoreRecord.new(attrs),
         {:ok, backend} <- BackendSelector.select(opts) do
      backend.put(record, opts)
    end
  end

  def put(attrs, opts) do
    with {:ok, _opts} <- normalize_opts(opts) do
      StateStoreRecord.new(attrs)
    end
  end

  @spec get(String.t(), map(), String.t(), String.t(), keyword()) ::
          {:ok, StateStoreRecord.t() | nil} | {:error, map()}
  def get(extension_id, workflow_scope, state_type, state_key, opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, backend} <- BackendSelector.select(opts) do
      backend.get(extension_id, workflow_scope, state_type, state_key, opts)
    end
  end

  @spec list(String.t(), map(), String.t(), keyword()) ::
          {:ok, [StateStoreRecord.t()]} | {:error, map()}
  def list(extension_id, workflow_scope, state_type, opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, backend} <- BackendSelector.select(opts) do
      backend.list(extension_id, workflow_scope, state_type, opts)
    end
  end

  @spec delete(String.t(), map(), String.t(), String.t(), keyword()) :: :ok | {:error, map()}
  def delete(extension_id, workflow_scope, state_type, state_key, opts \\ []) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, backend} <- BackendSelector.select(opts) do
      backend.delete(extension_id, workflow_scope, state_type, state_key, opts)
    end
  end

  defp normalize_opts(opts), do: Options.normalize(opts)
end
