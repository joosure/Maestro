defmodule SymphonyElixir.Storage.Config do
  @moduledoc """
  Platform storage configuration boundary.

  External runtime environment is loaded by config/runtime.exs. This module
  normalizes application configuration into stable platform backend identifiers
  so subsystem stores do not own physical database settings.
  """

  @app :symphony_elixir
  @config_key :storage

  @memory_backend :memory
  @sqlite_backend :sqlite
  @backends [@memory_backend, @sqlite_backend]
  @external_backend_values Enum.map(@backends, &Atom.to_string/1)
  @backend_values Map.new(@backends, &{&1, &1})
  @external_backend_value_map Map.new(@backends, &{Atom.to_string(&1), &1})
  @supported_backend_values Map.merge(@backend_values, @external_backend_value_map)

  @type backend :: :memory | :sqlite

  @spec backends() :: [backend()]
  def backends, do: @backends

  @spec external_backend_values() :: [String.t()]
  def external_backend_values, do: @external_backend_values

  @spec backend(keyword()) :: backend()
  def backend(opts \\ []) do
    case Keyword.fetch(opts, :platform_storage_backend) do
      {:ok, backend} ->
        normalize_backend!(backend, "opts[:platform_storage_backend]")

      :error ->
        configured_backend()
    end
  end

  @spec sqlite?(keyword()) :: boolean()
  def sqlite?(opts \\ []), do: backend(opts) == @sqlite_backend

  @spec durable?(keyword()) :: boolean()
  def durable?(opts \\ []), do: backend(opts) != @memory_backend

  defp configured_backend do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(:backend, @memory_backend)
    |> normalize_backend!("config #{inspect(@config_key)}[:backend]")
  end

  defp normalize_backend!(backend, source) do
    case Map.fetch(@supported_backend_values, backend) do
      {:ok, normalized_backend} ->
        normalized_backend

      :error ->
        raise ArgumentError,
              "unsupported platform storage backend #{inspect(backend)} from #{source}; " <>
                "expected one of #{inspect(Map.keys(@supported_backend_values))}"
    end
  end
end
