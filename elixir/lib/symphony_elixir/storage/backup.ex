defmodule SymphonyElixir.Storage.Backup do
  @moduledoc """
  Platform backup boundary for durable storage backends.

  Backup orchestration is infrastructure-owned. Domain stores and workflow
  plugins must not copy database files or invoke backend-specific backup
  commands directly.
  """

  alias SymphonyElixir.Storage.{Backend, Backup.DisabledBackend}

  @app :symphony_elixir
  @config_key :storage_backup

  @type result :: {:ok, map()} | {:error, map()}

  @callback create(keyword()) :: result()

  @spec create(keyword()) :: result()
  def create(opts \\ []) when is_list(opts) do
    with {:ok, backend} <- backend(opts) do
      backend.create(opts)
    end
  end

  defp backend(opts) do
    case Keyword.get(opts, :backend) || configured_backend() do
      module when is_atom(module) and not is_nil(module) ->
        case Backend.validate(module, __MODULE__, :create, 1) do
          :ok -> {:ok, module}
          {:error, _reason} = error -> error
        end

      value ->
        Backend.validate(value, __MODULE__, :create, 1)
    end
  end

  defp configured_backend do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(:backend, DisabledBackend)
  end
end
