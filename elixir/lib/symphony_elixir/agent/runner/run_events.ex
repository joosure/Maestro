defmodule SymphonyElixir.Agent.Runner.RunEvents do
  @moduledoc false

  alias SymphonyElixir.Agent.Runner.EventFields
  alias SymphonyElixir.Agent.Runner.TurnEvents
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @type worker_host :: String.t() | nil

  @spec emit_exception_terminal(
          term(),
          Exception.stacktrace(),
          term(),
          worker_host(),
          Path.t() | nil,
          String.t(),
          integer(),
          term()
        ) :: term()
  def emit_exception_terminal(exception, stacktrace, issue, worker_host, workspace, run_id, started_at_ms, attempt) do
    ObsLogger.emit(
      :error,
      :agent_run_failed,
      EventFields.event(
        issue,
        worker_host,
        workspace,
        %{
          run_id: run_id,
          correlation_id: run_id,
          status: "failed",
          attempt: attempt,
          duration_ms: elapsed_ms(started_at_ms),
          failure_class: "agent_run_exception"
        }
        |> Map.merge(ObsLogger.error_details(exception, stacktrace))
      )
    )
  end

  @spec emit_catch_terminal(
          atom(),
          term(),
          Exception.stacktrace(),
          term(),
          worker_host(),
          Path.t() | nil,
          String.t(),
          integer(),
          term()
        ) :: term()
  def emit_catch_terminal(kind, reason, stacktrace, issue, worker_host, workspace, run_id, started_at_ms, attempt) do
    event = catch_terminal_event(kind, reason)
    status = if event == :agent_run_cancelled, do: "cancelled", else: "failed"
    failure_class = if event == :agent_run_cancelled, do: "cancelled", else: TurnEvents.run_failure_class(reason, worker_host)
    level = if event == :agent_run_cancelled, do: :warning, else: :error

    ObsLogger.emit(
      level,
      event,
      EventFields.event(
        issue,
        worker_host,
        workspace,
        %{
          run_id: run_id,
          correlation_id: run_id,
          status: status,
          attempt: attempt,
          duration_ms: elapsed_ms(started_at_ms),
          failure_class: failure_class
        }
        |> Map.merge(ObsLogger.error_details({kind, reason}, stacktrace))
      )
    )
  end

  defp catch_terminal_event(:exit, :shutdown), do: :agent_run_cancelled
  defp catch_terminal_event(:exit, :normal), do: :agent_run_cancelled
  defp catch_terminal_event(:exit, :cancelled), do: :agent_run_cancelled
  defp catch_terminal_event(:exit, {:shutdown, _reason}), do: :agent_run_cancelled
  defp catch_terminal_event(_kind, _reason), do: :agent_run_failed

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
  defp elapsed_ms(started_at_ms), do: max(monotonic_ms() - started_at_ms, 0)
end
