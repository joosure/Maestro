defmodule SymphonyElixir.Observability.StatusDashboard.RenderFailure do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @spec emit(atom(), String.t(), term()) :: :ok
  def emit(event, phase, error) do
    formatted_error = format_error(error)

    ObservabilityLogger.emit(
      :warning,
      event,
      %{
        component: "status_dashboard",
        error: formatted_error,
        result_summary: "phase=#{phase}",
        message: "#{event} phase=#{phase} error=#{formatted_error}"
      }
    )

    :ok
  end

  @spec format_error(term()) :: String.t()
  def format_error(error), do: ObservabilityLogger.format_error(error)
end
