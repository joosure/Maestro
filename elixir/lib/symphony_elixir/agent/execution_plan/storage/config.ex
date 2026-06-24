defmodule SymphonyElixir.Agent.ExecutionPlan.Storage.Config do
  @moduledoc """
  Agent execution-plan storage mode configuration.

  The Agent domain owns whether execution plans are in-memory or durable.
  Physical storage backend selection belongs to `SymphonyElixir.Storage.Config`.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Storage.MemoryBackend
  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLiteBackend
  alias SymphonyElixir.Storage.Config, as: PlatformStorageConfig

  @app :symphony_elixir
  @config_key :agent_execution_plan
  @backend_opt_key :backend
  @storage_mode_opt_key :storage_mode
  @storage_config_key :storage
  @memory_mode :memory
  @durable_mode :durable
  @memory_mode_string Atom.to_string(@memory_mode)
  @durable_mode_string Atom.to_string(@durable_mode)

  @type backend :: module()
  @type storage_mode :: :memory | :durable

  @spec backend(keyword()) :: backend()
  def backend(opts \\ []) do
    case Keyword.fetch(opts, @backend_opt_key) do
      {:ok, backend} ->
        normalize_backend_module!(backend, option_source(@backend_opt_key))

      :error ->
        opts
        |> storage_mode()
        |> backend_for_mode(opts)
    end
  end

  @spec storage_mode(keyword()) :: storage_mode()
  def storage_mode(opts \\ []) do
    case Keyword.fetch(opts, @storage_mode_opt_key) do
      {:ok, mode} ->
        normalize_storage_mode!(mode, option_source(@storage_mode_opt_key))

      :error ->
        configured_storage_mode()
    end
  end

  @spec durable?(keyword()) :: boolean()
  def durable?(opts \\ []), do: storage_mode(opts) == @durable_mode

  defp configured_storage_mode do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(@storage_config_key, @memory_mode)
    |> normalize_storage_mode!(config_source(@storage_config_key))
  end

  defp backend_for_mode(@memory_mode, _opts), do: MemoryBackend

  defp backend_for_mode(@durable_mode, opts) do
    case PlatformStorageConfig.backend(opts) do
      :sqlite ->
        SQLiteBackend

      :memory ->
        raise ArgumentError,
              "Agent execution-plan storage mode :durable requires a durable platform storage backend; " <>
                "configured platform backend :memory"
    end
  end

  defp normalize_backend_module!(MemoryBackend, _source), do: MemoryBackend
  defp normalize_backend_module!(SQLiteBackend, _source), do: SQLiteBackend

  defp normalize_backend_module!(backend, source) do
    raise ArgumentError,
          "unsupported Agent execution-plan storage backend #{inspect(backend)} from #{source}; " <>
            "expected #{inspect(MemoryBackend)} or #{inspect(SQLiteBackend)}"
  end

  defp normalize_storage_mode!(@memory_mode, _source), do: @memory_mode
  defp normalize_storage_mode!(@durable_mode, _source), do: @durable_mode
  defp normalize_storage_mode!(@memory_mode_string, _source), do: @memory_mode
  defp normalize_storage_mode!(@durable_mode_string, _source), do: @durable_mode

  defp normalize_storage_mode!(mode, source) do
    raise ArgumentError,
          "unsupported Agent execution-plan storage mode #{inspect(mode)} from #{source}; " <>
            "expected #{mode_expectation()}"
  end

  defp option_source(key), do: "opts[:#{key}]"
  defp config_source(key), do: "config #{inspect(@config_key)}[:#{key}]"

  defp mode_expectation do
    "#{inspect(@memory_mode)}, #{inspect(@durable_mode)}, #{inspect(@memory_mode_string)}, or #{inspect(@durable_mode_string)}"
  end
end
