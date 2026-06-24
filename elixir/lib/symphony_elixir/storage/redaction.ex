defmodule SymphonyElixir.Storage.Redaction do
  @moduledoc """
  Platform redaction boundary for storage diagnostics and operator surfaces.

  Domain-specific redaction remains subsystem-owned. This boundary provides the
  shared fallback used by storage infrastructure before emitting diagnostics or
  operator-inspection payloads.
  """

  alias SymphonyElixir.Storage.{Backend, Redaction.DefaultBackend}

  @app :symphony_elixir
  @config_key :storage_redaction

  @callback redact(term(), keyword()) :: term()

  @spec redact(term(), keyword()) :: term() | {:error, map()}
  def redact(value, opts \\ []) when is_list(opts) do
    with {:ok, backend} <- backend(opts) do
      backend.redact(value, opts)
    end
  end

  defp backend(opts) do
    case Keyword.get(opts, :backend) || configured_backend() do
      module when is_atom(module) and not is_nil(module) ->
        case Backend.validate(module, __MODULE__, :redact, 2) do
          :ok -> {:ok, module}
          {:error, _reason} = error -> error
        end

      value ->
        Backend.validate(value, __MODULE__, :redact, 2)
    end
  end

  defp configured_backend do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(:backend, DefaultBackend)
  end
end
