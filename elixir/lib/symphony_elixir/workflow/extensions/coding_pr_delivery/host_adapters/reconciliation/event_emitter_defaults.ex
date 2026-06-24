defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.EventEmitterDefaults do
  @moduledoc false

  @behaviour SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Emitter

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @impl true
  def emit(level, event, fields), do: ObservabilityLogger.emit(level, event, fields)
end
