defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Emitter do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.EventEmitterDefaults, as: Defaults

  @callback emit(atom(), atom(), map()) :: term()

  @spec emit(atom(), atom(), map(), keyword()) :: term()
  def emit(level, event, fields, opts \\ []) when is_atom(level) and is_atom(event) and is_map(fields) do
    case backend(opts) do
      {:ok, backend} ->
        with :ok <- validate_backend(backend) do
          backend.emit(level, event, fields)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp backend(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, Keyword.get(opts, :backend, Defaults)}
    else
      invalid_options(opts)
    end
  end

  defp backend(opts), do: invalid_options(opts)

  defp invalid_options(opts) do
    {:error,
     %{
       code: :invalid_reconciliation_event_emitter_options,
       value_type: Diagnostics.type_name(opts)
     }}
  end

  defp validate_backend(backend) when is_atom(backend) do
    if Code.ensure_loaded?(backend) and function_exported?(backend, :emit, 3) do
      :ok
    else
      invalid_backend(backend)
    end
  end

  defp validate_backend(backend), do: invalid_backend(backend)

  defp invalid_backend(backend) do
    {:error,
     %{
       code: :invalid_reconciliation_event_emitter_backend,
       value_type: Diagnostics.type_name(backend)
     }}
  end
end
