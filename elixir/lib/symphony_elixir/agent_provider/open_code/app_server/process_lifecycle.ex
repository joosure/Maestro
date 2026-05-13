defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.ProcessLifecycle do
  @moduledoc false

  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @shutdown_grace_ms 500
  @shutdown_kill_wait_ms 500

  @spec stop_port(port()) :: :ok
  def stop_port(port) when is_port(port) do
    os_pid = PlatformProcess.port_os_pid(port)
    PlatformProcess.close_port(port)

    PlatformProcess.terminate_os_process(os_pid,
      process_group?: true,
      initial_signal?: false,
      grace_ms: @shutdown_grace_ms,
      kill_wait_ms: @shutdown_kill_wait_ms
    )

    :ok
  end
end
