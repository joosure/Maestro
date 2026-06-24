defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.Config do
  @moduledoc """
  Workflow structured execution-plan adoption storage mode configuration.

  Workflow adoption owns its envelope storage mode. Physical storage backend
  selection belongs to `SymphonyElixir.Storage.Config`.
  """

  alias SymphonyElixir.Storage.Config, as: PlatformStorageConfig
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.MemoryBackend
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLiteBackend

  @app :symphony_elixir
  @config_key :workflow_execution_plan_adoption

  @type backend :: module()
  @type storage_mode :: :memory | :durable

  @spec backend(keyword()) :: backend()
  def backend(opts \\ []) do
    case Keyword.fetch(opts, :workflow_storage_backend) do
      {:ok, backend} ->
        normalize_backend_module!(backend, "opts[:workflow_storage_backend]")

      :error ->
        opts
        |> storage_mode()
        |> backend_for_mode(opts)
    end
  end

  @spec storage_mode(keyword()) :: storage_mode()
  def storage_mode(opts \\ []) do
    case Keyword.fetch(opts, :workflow_storage_mode) do
      {:ok, mode} ->
        normalize_storage_mode!(mode, "opts[:workflow_storage_mode]")

      :error ->
        configured_storage_mode()
    end
  end

  @spec durable?(keyword()) :: boolean()
  def durable?(opts \\ []), do: storage_mode(opts) == :durable

  defp configured_storage_mode do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(:storage, :memory)
    |> normalize_storage_mode!("config #{inspect(@config_key)}[:storage]")
  end

  defp backend_for_mode(:memory, _opts), do: MemoryBackend

  defp backend_for_mode(:durable, opts) do
    case PlatformStorageConfig.backend(opts) do
      :sqlite ->
        SQLiteBackend

      :memory ->
        raise ArgumentError,
              "Workflow structured execution-plan storage mode :durable requires a durable platform storage backend; " <>
                "configured platform backend :memory"
    end
  end

  defp normalize_backend_module!(MemoryBackend, _source), do: MemoryBackend
  defp normalize_backend_module!(SQLiteBackend, _source), do: SQLiteBackend

  defp normalize_backend_module!(backend, source) do
    raise ArgumentError,
          "unsupported Workflow structured execution-plan storage backend #{inspect(backend)} from #{source}; " <>
            "expected #{inspect(MemoryBackend)} or #{inspect(SQLiteBackend)}"
  end

  defp normalize_storage_mode!(:memory, _source), do: :memory
  defp normalize_storage_mode!(:durable, _source), do: :durable
  defp normalize_storage_mode!("memory", _source), do: :memory
  defp normalize_storage_mode!("durable", _source), do: :durable

  defp normalize_storage_mode!(mode, source) do
    raise ArgumentError,
          "unsupported Workflow structured execution-plan storage mode #{inspect(mode)} from #{source}; " <>
            "expected :memory, :durable, \"memory\", or \"durable\""
  end
end
