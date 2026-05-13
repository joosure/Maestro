defmodule SymphonyWorkerDaemon.ProcessRunner do
  @moduledoc false

  alias SymphonyElixir.Platform.Process, as: PlatformProcess
  alias SymphonyWorkerDaemon.ProcessRunner.{Environment, StopOptions}

  @spec start(map(), Path.t(), map(), keyword()) :: {:ok, port()} | {:error, term()}
  def start(command, cwd, env \\ %{}, opts \\ [])

  def start(%{"mode" => "argv", "argv" => [_command | _args] = argv}, cwd, env, opts)
      when is_binary(cwd) and is_map(env) and is_list(opts) do
    PlatformProcess.start_argv(argv, cwd: cwd, env: Environment.stringify(env), line: Keyword.get(opts, :line))
  end

  def start(%{"mode" => "shell", "command" => command}, cwd, env, opts)
      when is_binary(command) and is_binary(cwd) and is_map(env) and is_list(opts) do
    if Keyword.get(opts, :allow_shell?, false) do
      PlatformProcess.start_shell(command, cwd: cwd, env: Environment.stringify(env), line: Keyword.get(opts, :line))
    else
      {:error, :shell_command_disabled}
    end
  end

  def start(%{"mode" => "unset"}, _cwd, _env, _opts), do: {:error, :command_unset}
  def start(_command, _cwd, _env, _opts), do: {:error, :command_invalid}

  @spec stop(term(), keyword()) :: :ok
  def stop(port, opts \\ [])

  def stop(port, opts) when is_port(port) and is_list(opts) do
    port
    |> PlatformProcess.port_os_pid()
    |> PlatformProcess.terminate_os_process(StopOptions.build(opts))

    PlatformProcess.close_port(port)
    :ok
  end

  def stop(_handle, _opts), do: :ok

  @spec alive?(term()) :: boolean()
  def alive?(port) when is_port(port), do: PlatformProcess.port_alive?(port)
  def alive?(_handle), do: false

  @spec os_pid(term()) :: pos_integer() | nil
  def os_pid(port) when is_port(port), do: PlatformProcess.port_os_pid(port)
  def os_pid(_handle), do: nil
end
