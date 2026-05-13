defmodule SymphonyElixir.Agent.Runtime.Executor.SSH do
  @moduledoc false

  @behaviour SymphonyElixir.Agent.Runtime.Executor

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Platform.Process, as: PlatformProcess
  alias SymphonyElixir.Platform.SSH

  @impl true
  @spec start(CommandSpec.t(), Target.t(), keyword()) :: {:ok, port()} | {:error, term()}
  def start(command_spec, target, opts \\ [])

  def start(%CommandSpec{} = command_spec, %Target{worker_host: nil}, _opts) do
    {:error, {:remote_worker_host_missing, CommandSpec.command_summary(command_spec)}}
  end

  def start(%CommandSpec{command: command}, %Target{worker_host: worker_host}, opts) when is_binary(command) do
    SSH.start_port(worker_host, command, opts)
  end

  def start(%CommandSpec{argv: [_command | _args] = argv}, %Target{worker_host: worker_host}, opts) do
    SSH.start_port(worker_host, shell_join(argv), opts)
  end

  def start(%CommandSpec{} = command_spec, %Target{worker_host: worker_host}, _opts) do
    {:error, {:invalid_remote_command_spec, worker_host, CommandSpec.command_summary(command_spec)}}
  end

  @impl true
  @spec stop(term(), keyword()) :: :ok | {:error, term()}
  def stop(handle, opts \\ [])

  def stop(port, _opts) when is_port(port) do
    PlatformProcess.close_port(port)
  end

  def stop(_handle, _opts), do: :ok

  @impl true
  @spec alive?(term()) :: boolean()
  def alive?(port) when is_port(port), do: PlatformProcess.port_alive?(port)
  def alive?(_handle), do: false

  defp shell_join(argv) when is_list(argv), do: Enum.map_join(argv, " ", &shell_escape/1)

  defp shell_escape(value) do
    "'#{String.replace(to_string(value), "'", "'\"'\"'")}'"
  end
end
