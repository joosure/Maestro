defmodule SymphonyElixir.Agent.Runtime.Executor.Local do
  @moduledoc false

  @behaviour SymphonyElixir.Agent.Runtime.Executor

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @impl true
  @spec start(CommandSpec.t(), Target.t(), keyword()) :: {:ok, port()} | {:error, term()}
  def start(command_spec, target, opts \\ [])

  def start(%CommandSpec{argv: [command | args]} = command_spec, %Target{} = target, opts) do
    env = Map.merge(target.env, command_spec.env)
    cwd = command_spec.cwd || target.workspace_path

    PlatformProcess.start_argv([command | args], cwd: cwd, env: env, line: Keyword.get(opts, :line))
  end

  def start(%CommandSpec{command: command} = command_spec, %Target{} = target, opts)
      when is_binary(command) do
    env = Map.merge(target.env, command_spec.env)
    cwd = command_spec.cwd || target.workspace_path

    PlatformProcess.start_shell(command, cwd: cwd, env: env, line: Keyword.get(opts, :line))
  end

  def start(%CommandSpec{} = command_spec, %Target{}, _opts), do: {:error, {:invalid_command_spec, CommandSpec.command_summary(command_spec)}}

  @impl true
  @spec stop(term(), keyword()) :: :ok | {:error, term()}
  def stop(handle, opts \\ [])

  def stop(port, opts) when is_port(port) do
    os_pid = PlatformProcess.port_os_pid(port)
    PlatformProcess.close_port(port)

    PlatformProcess.terminate_os_process(os_pid,
      initial_signal?: false,
      grace_ms: Keyword.get(opts, :grace_ms, 500),
      kill_wait_ms: Keyword.get(opts, :kill_wait_ms, 500),
      poll_ms: Keyword.get(opts, :poll_ms, 25)
    )

    :ok
  end

  def stop(_handle, _opts), do: :ok

  @impl true
  @spec alive?(term()) :: boolean()
  def alive?(handle), do: PlatformProcess.port_alive?(handle)
end
