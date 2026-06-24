defmodule SymphonyElixir.Workflow.Extension.StateStore.BackendSelector do
  @moduledoc """
  Backend selection and behaviour validation for workflow extension state storage.
  """

  alias SymphonyElixir.Storage
  alias SymphonyElixir.Workflow.Extension.StateStore
  alias SymphonyElixir.Workflow.Extension.StateStore.Config
  alias SymphonyElixir.Workflow.Extension.StateStore.MemoryBackend
  alias SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLiteBackend

  @spec select(keyword()) :: {:ok, module()} | {:error, term()}
  def select(opts) do
    with {:ok, configured_backend} <- Config.configured_backend(),
         backend <- Keyword.get(opts, :backend) || configured_backend || default_backend(),
         :ok <- Storage.Backend.validate(backend, StateStore, :put, 2),
         :ok <- Storage.Backend.validate(backend, StateStore, :get, 5),
         :ok <- Storage.Backend.validate(backend, StateStore, :list, 4),
         :ok <- Storage.Backend.validate(backend, StateStore, :delete, 5) do
      {:ok, backend}
    end
  end

  defp default_backend do
    if Storage.Config.sqlite?() do
      SQLiteBackend
    else
      MemoryBackend
    end
  end
end
