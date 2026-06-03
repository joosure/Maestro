defmodule SymphonyElixir.AgentProvider.Codex.AppServer.ProcessLifecycle do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{Handle, LocalProcess}
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @spec stop_port(term(), map()) :: :ok
  def stop_port(port, context_fields) when is_port(port) and is_map(context_fields) do
    os_pid = PlatformProcess.port_os_pid(port)

    termination = ensure_os_process_exit(os_pid, context_fields)
    PlatformProcess.close_port(port)

    if not Map.get(termination, :alive?) do
      LocalProcess.unregister(port)
    end
  end

  def stop_port(handle, _context_fields), do: Handle.close(handle)

  defp ensure_os_process_exit(nil, _context_fields), do: %{alive?: false}

  defp ensure_os_process_exit(os_pid, context_fields)
       when is_integer(os_pid) and os_pid > 0 and is_map(context_fields) do
    result =
      PlatformProcess.terminate_os_process_tree(os_pid,
        process_group?: true,
        initial_signal?: false,
        grace_ms: 500,
        kill_wait_ms: 500,
        poll_ms: 50
      )

    Enum.each(result.signals_sent, fn signal ->
      emit_process_stop_event(
        :warning,
        :codex_session_process_termination_escalated,
        os_pid,
        "-#{signal}",
        context_fields
      )
    end)

    if result.alive? do
      emit_process_stop_failure(os_pid, context_fields)
    end

    result
  end

  defp emit_process_stop_event(level, event, os_pid, signal, context_fields)
       when is_integer(os_pid) and is_binary(signal) and is_map(context_fields) do
    ObsLogger.emit(
      level,
      event,
      context_fields
      |> Map.put_new(:component, "codex.app_server")
      |> Map.put(:operation_name, "terminate_os_process_tree")
      |> Map.put(:message, "#{event} signal=#{signal} os_pid=#{os_pid}")
      |> Map.put(:result_summary, "signal=#{signal}")
      |> Map.put(:payload_summary, "os_pid=#{os_pid}")
    )
  end

  defp emit_process_stop_failure(os_pid, context_fields)
       when is_integer(os_pid) and is_map(context_fields) do
    ObsLogger.emit(
      :error,
      :codex_session_process_termination_incomplete,
      context_fields
      |> Map.put_new(:component, "codex.app_server")
      |> Map.put(:operation_name, "terminate_os_process_tree")
      |> Map.put(:message, "codex_session_process_termination_incomplete os_pid=#{os_pid}")
      |> Map.put(:error, "os_process_still_alive")
      |> Map.put(:payload_summary, "os_pid=#{os_pid}")
    )
  end
end
