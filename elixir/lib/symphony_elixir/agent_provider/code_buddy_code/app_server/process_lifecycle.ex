defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.ProcessLifecycle do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{Handle, LocalProcess}
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @shutdown_grace_ms 500
  @shutdown_kill_wait_ms 500

  @spec stop_port(term()) :: :ok | {:error, term()}
  def stop_port(port) when is_port(port) do
    case :erlang.port_info(port) do
      :undefined ->
        LocalProcess.unregister(port)

      _info ->
        termination =
          port
          |> PlatformProcess.port_os_pid()
          |> PlatformProcess.terminate_os_process_tree(
            process_group?: true,
            grace_ms: @shutdown_grace_ms,
            kill_wait_ms: @shutdown_kill_wait_ms
          )

        PlatformProcess.close_port(port)

        if not Map.get(termination, :alive?) do
          LocalProcess.unregister(port)
        end
    end
  end

  def stop_port(handle), do: Handle.close(handle)
end
