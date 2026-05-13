defmodule SymphonyElixir.Orchestrator.IgnoredMessage do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Observability.Redaction

  @spec log(term()) :: :ok
  def log(message) do
    ObservabilityLogger.text(
      :debug,
      "orchestrator_ignored_message",
      fields(message)
    )
  end

  @spec fields(term()) :: map()
  def fields(message) do
    %{
      event: :orchestrator_ignored_message,
      component: "orchestrator",
      payload_summary: Redaction.summarize(message, 256)
    }
  end
end
