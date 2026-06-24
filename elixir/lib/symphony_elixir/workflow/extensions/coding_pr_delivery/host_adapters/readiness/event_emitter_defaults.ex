defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.EventEmitterDefaults do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @spec emit(atom(), atom(), map()) :: term()
  def emit(level, event, fields), do: ObservabilityLogger.emit(level, event, fields)
end
