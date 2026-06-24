defmodule SymphonyElixir.Storage.Retention do
  @moduledoc """
  Platform retention boundary for durable storage.

  Retention policies are platform-governed. Subsystems may declare retention
  requirements in their own specs, but pruning execution belongs to this
  infrastructure boundary.
  """

  alias SymphonyElixir.Storage.{Backend, Retention.NoopBackend}

  @app :symphony_elixir
  @config_key :storage_retention

  @type result :: {:ok, map()} | {:error, map()}

  @callback prune(keyword()) :: result()

  @spec prune(keyword()) :: result()
  def prune(opts \\ []) when is_list(opts) do
    with {:ok, backend} <- backend(opts) do
      backend.prune(opts)
    end
  end

  defp backend(opts) do
    case Keyword.get(opts, :backend) || configured_backend() do
      module when is_atom(module) and not is_nil(module) ->
        case Backend.validate(module, __MODULE__, :prune, 1) do
          :ok -> {:ok, module}
          {:error, _reason} = error -> error
        end

      value ->
        Backend.validate(value, __MODULE__, :prune, 1)
    end
  end

  defp configured_backend do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(:backend, NoopBackend)
  end
end
