defmodule SymphonyElixir.Platform.Process do
  @moduledoc false

  alias SymphonyElixir.Platform.CommandEnv

  @default_grace_ms 500
  @default_kill_wait_ms 500
  @default_poll_ms 25

  @type terminate_result :: %{
          required(:os_pid) => pos_integer() | nil,
          required(:signals_sent) => [String.t()],
          required(:alive?) => boolean() | nil,
          optional(:descendant_pids) => [pos_integer()]
        }

  @spec start_argv([String.t()], keyword()) :: {:ok, port()} | {:error, term()}
  def start_argv(argv, opts \\ [])

  def start_argv([command | args], opts) when is_binary(command) and is_list(args) do
    cwd = cwd(opts)
    env = env(opts)

    case resolve_executable(command, cwd) do
      {:ok, executable} ->
        open_port(executable, Enum.map(args, &to_string/1), cwd, env, opts)

      {:error, _reason} = error ->
        error
    end
  end

  def start_argv(_argv, _opts), do: {:error, :invalid_argv}

  @spec start_shell(String.t(), keyword()) :: {:ok, port()} | {:error, term()}
  def start_shell(command, opts \\ []) when is_binary(command) do
    case System.find_executable("bash") do
      nil -> {:error, :bash_not_found}
      executable -> open_port(executable, ["-lc", command], cwd(opts), env(opts), opts)
    end
  end

  @spec close_port(term()) :: :ok
  def close_port(port) when is_port(port) do
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def close_port(_handle), do: :ok

  @spec port_alive?(term()) :: boolean()
  def port_alive?(port) when is_port(port), do: :erlang.port_info(port) != :undefined
  def port_alive?(_handle), do: false

  @spec port_os_pid(term()) :: pos_integer() | nil
  def port_os_pid(port) when is_port(port) do
    case :erlang.port_info(port, :os_pid) do
      {:os_pid, os_pid} when is_integer(os_pid) and os_pid > 0 -> os_pid
      _ -> nil
    end
  end

  def port_os_pid(_handle), do: nil

  @spec terminate_os_process(pos_integer() | nil, keyword()) :: terminate_result()
  def terminate_os_process(os_pid, opts \\ [])

  def terminate_os_process(nil, _opts), do: %{os_pid: nil, signals_sent: [], alive?: nil}

  def terminate_os_process(os_pid, opts) when is_integer(os_pid) and os_pid > 0 and is_list(opts) do
    process_group? = Keyword.get(opts, :process_group?, false)
    initial_signal? = Keyword.get(opts, :initial_signal?, true)
    grace_ms = non_negative_integer(opts, :grace_ms, @default_grace_ms)
    kill_wait_ms = non_negative_integer(opts, :kill_wait_ms, @default_kill_wait_ms)
    poll_ms = positive_integer(opts, :poll_ms, @default_poll_ms)

    {signals_sent, alive?} =
      if initial_signal? do
        terminate_after_signal(os_pid, process_group?, grace_ms, kill_wait_ms, poll_ms, [])
      else
        terminate_after_wait(os_pid, process_group?, grace_ms, kill_wait_ms, poll_ms, [])
      end

    %{os_pid: os_pid, signals_sent: signals_sent, alive?: alive?}
  end

  def terminate_os_process(_os_pid, _opts), do: %{os_pid: nil, signals_sent: [], alive?: nil}

  @spec terminate_os_process_tree(pos_integer() | nil, keyword()) :: terminate_result()
  def terminate_os_process_tree(os_pid, opts \\ [])

  def terminate_os_process_tree(nil, _opts), do: %{os_pid: nil, signals_sent: [], alive?: nil, descendant_pids: []}

  def terminate_os_process_tree(os_pid, opts) when is_integer(os_pid) and os_pid > 0 and is_list(opts) do
    descendant_pids = descendant_os_pids(os_pid)
    root_result = terminate_os_process(os_pid, opts)

    remaining_descendant_pids =
      (descendant_pids ++ descendant_os_pids(os_pid))
      |> Enum.uniq()
      |> Enum.reject(&(&1 == os_pid))

    descendant_opts = Keyword.put(opts, :process_group?, false)

    descendant_results =
      Enum.map(remaining_descendant_pids, fn descendant_pid ->
        terminate_os_process(descendant_pid, descendant_opts)
      end)

    alive? =
      root_result.alive? or
        Enum.any?(descendant_results, fn
          %{alive?: true} -> true
          _result -> false
        end)

    root_result
    |> Map.put(:alive?, alive?)
    |> Map.put(:descendant_pids, remaining_descendant_pids)
  end

  def terminate_os_process_tree(_os_pid, _opts), do: %{os_pid: nil, signals_sent: [], alive?: nil, descendant_pids: []}

  @spec signal_os_process(pos_integer(), String.t(), keyword()) :: :ok
  def signal_os_process(os_pid, signal, opts \\ [])
      when is_integer(os_pid) and os_pid > 0 and is_binary(signal) and is_list(opts) do
    case System.find_executable("kill") do
      nil ->
        :ok

      kill_executable ->
        signal_arg = normalize_signal_arg(signal)

        if Keyword.get(opts, :process_group?, false) do
          case CommandEnv.system_cmd(kill_executable, [signal_arg, "--", "-#{os_pid}"], stderr_to_stdout: true) do
            {_output, 0} ->
              :ok

            _other ->
              signal_pid(kill_executable, signal_arg, os_pid)
          end
        else
          signal_pid(kill_executable, signal_arg, os_pid)
        end
    end
  rescue
    _error -> :ok
  end

  @spec os_process_alive?(pos_integer() | nil) :: boolean()
  def os_process_alive?(os_pid) when is_integer(os_pid) and os_pid > 0 do
    case System.find_executable("ps") do
      nil ->
        os_process_alive_with_kill?(os_pid)

      ps_executable ->
        case CommandEnv.system_cmd(ps_executable, ["-o", "stat=", "-p", Integer.to_string(os_pid)], stderr_to_stdout: true) do
          {output, 0} ->
            case String.trim(output) do
              "" -> false
              <<"Z", _::binary>> -> false
              _status -> true
            end

          _other ->
            false
        end
    end
  end

  def os_process_alive?(_os_pid), do: false

  @spec descendant_os_pids(pos_integer() | nil) :: [pos_integer()]
  def descendant_os_pids(os_pid) when is_integer(os_pid) and os_pid > 0 do
    collect_descendant_os_pids([os_pid], MapSet.new([os_pid]), [])
  end

  def descendant_os_pids(_os_pid), do: []

  @spec wait_for_os_process_exit(pos_integer(), non_neg_integer(), pos_integer()) :: boolean()
  def wait_for_os_process_exit(os_pid, remaining_ms, poll_ms)
      when is_integer(os_pid) and os_pid > 0 and is_integer(remaining_ms) and is_integer(poll_ms) do
    do_wait_for_os_process_exit(os_pid, max(remaining_ms, 0), max(poll_ms, 1))
  end

  @spec resolve_executable(String.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def resolve_executable(command, cwd \\ File.cwd!()) when is_binary(command) and is_binary(cwd) do
    cond do
      String.contains?(command, "/") and Path.type(command) == :absolute ->
        resolve_executable_path(command, command)

      String.contains?(command, "/") ->
        command
        |> Path.expand(cwd)
        |> resolve_executable_path(command)

      executable = System.find_executable(command) ->
        {:ok, executable}

      true ->
        {:error, {:command_not_found, command}}
    end
  end

  defp open_port(executable, args, cwd, env, opts) do
    if File.dir?(cwd) do
      {:ok,
       Port.open(
         {:spawn_executable, String.to_charlist(executable)},
         [
           :binary,
           :exit_status,
           :stderr_to_stdout,
           args: Enum.map(args, &String.to_charlist/1),
           cd: String.to_charlist(cwd),
           env: port_env(env)
         ]
         |> maybe_put_line(opts)
       )}
    else
      {:error, {:invalid_cwd, cwd}}
    end
  rescue
    error in [ArgumentError, ErlangError] ->
      {:error, {:port_open_failed, executable, Exception.message(error)}}
  end

  defp terminate_after_signal(os_pid, process_group?, grace_ms, kill_wait_ms, poll_ms, signals_sent) do
    signal_os_process(os_pid, "TERM", process_group?: process_group?)

    signals_sent = signals_sent ++ ["TERM"]

    if wait_for_os_process_exit(os_pid, grace_ms, poll_ms) do
      {signals_sent, false}
    else
      signal_os_process(os_pid, "KILL", process_group?: process_group?)

      signals_sent = signals_sent ++ ["KILL"]
      {signals_sent, os_process_alive_after_wait?(os_pid, kill_wait_ms, poll_ms)}
    end
  end

  defp terminate_after_wait(os_pid, process_group?, grace_ms, kill_wait_ms, poll_ms, signals_sent) do
    if wait_for_os_process_exit(os_pid, grace_ms, poll_ms) do
      {signals_sent, false}
    else
      terminate_after_signal(os_pid, process_group?, kill_wait_ms, kill_wait_ms, poll_ms, signals_sent)
    end
  end

  defp os_process_alive_after_wait?(os_pid, wait_ms, poll_ms) do
    not wait_for_os_process_exit(os_pid, wait_ms, poll_ms)
  end

  defp collect_descendant_os_pids([], _seen, descendants), do: Enum.reverse(descendants)

  defp collect_descendant_os_pids([parent_pid | rest], seen, descendants) do
    child_pids =
      parent_pid
      |> child_os_pids()
      |> Enum.reject(&MapSet.member?(seen, &1))

    seen = Enum.reduce(child_pids, seen, &MapSet.put(&2, &1))
    collect_descendant_os_pids(rest ++ child_pids, seen, child_pids ++ descendants)
  end

  defp child_os_pids(os_pid) do
    case child_os_pids_with_pgrep(os_pid) do
      :unavailable -> child_os_pids_with_ps(os_pid)
      child_pids -> child_pids
    end
  end

  defp child_os_pids_with_pgrep(os_pid) do
    case System.find_executable("pgrep") do
      nil ->
        :unavailable

      pgrep_executable ->
        case CommandEnv.system_cmd(pgrep_executable, ["-P", Integer.to_string(os_pid)], stderr_to_stdout: true) do
          {output, 0} -> positive_integer_lines(output)
          {_output, 1} -> []
          _other -> :unavailable
        end
    end
  rescue
    _error -> :unavailable
  end

  defp child_os_pids_with_ps(os_pid) do
    case System.find_executable("ps") do
      nil ->
        []

      ps_executable ->
        case CommandEnv.system_cmd(ps_executable, ["-eo", "pid=,ppid="], stderr_to_stdout: true) do
          {output, 0} ->
            output
            |> String.split("\n", trim: true)
            |> Enum.flat_map(&pid_ppid_pair/1)
            |> Enum.flat_map(fn
              {pid, ^os_pid} -> [pid]
              _pair -> []
            end)

          _other ->
            []
        end
    end
  rescue
    _error -> []
  end

  defp do_wait_for_os_process_exit(os_pid, 0, _poll_ms), do: not os_process_alive?(os_pid)

  defp do_wait_for_os_process_exit(os_pid, remaining_ms, poll_ms) do
    if os_process_alive?(os_pid) do
      Elixir.Process.sleep(min(poll_ms, remaining_ms))
      do_wait_for_os_process_exit(os_pid, max(remaining_ms - poll_ms, 0), poll_ms)
    else
      true
    end
  end

  defp signal_pid(kill_executable, signal_arg, os_pid) do
    _ = CommandEnv.system_cmd(kill_executable, [signal_arg, "--", Integer.to_string(os_pid)], stderr_to_stdout: true)
    :ok
  end

  defp os_process_alive_with_kill?(os_pid) when is_integer(os_pid) and os_pid > 0 do
    case System.find_executable("kill") do
      nil ->
        false

      kill_executable ->
        case CommandEnv.system_cmd(kill_executable, ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true) do
          {_output, 0} -> true
          _other -> false
        end
    end
  end

  defp positive_integer_lines(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Integer.parse(String.trim(line)) do
        {pid, ""} when pid > 0 -> [pid]
        _other -> []
      end
    end)
  end

  defp pid_ppid_pair(line) when is_binary(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [pid_text, ppid_text | _rest] ->
        with {pid, ""} when pid > 0 <- Integer.parse(pid_text),
             {ppid, ""} when ppid > 0 <- Integer.parse(ppid_text) do
          [{pid, ppid}]
        else
          _other -> []
        end

      _parts ->
        []
    end
  end

  defp resolve_executable_path(path, command) do
    cond do
      not File.exists?(path) ->
        {:error, {:command_not_found, command}}

      executable_file?(path) ->
        {:ok, path}

      true ->
        {:error, {:command_not_executable, command}}
    end
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _other -> false
    end
  end

  defp cwd(opts) do
    case Keyword.get(opts, :cwd, File.cwd!()) do
      cwd when is_binary(cwd) -> cwd
      cwd -> to_string(cwd)
    end
  end

  defp env(opts) do
    case Keyword.get(opts, :env, %{}) do
      env when is_map(env) or is_list(env) -> CommandEnv.merge(env)
      _env -> CommandEnv.merge(%{})
    end
  end

  defp port_env(env) when is_map(env) do
    Enum.map(env, fn {key, value} -> {String.to_charlist(to_string(key)), env_value_to_charlist(value)} end)
  end

  defp port_env(env) when is_list(env), do: env |> Map.new() |> port_env()

  defp env_value_to_charlist(nil), do: false
  defp env_value_to_charlist(value), do: value |> to_string() |> String.to_charlist()

  defp maybe_put_line(port_options, opts) when is_list(opts) do
    case Keyword.get(opts, :line) do
      line when is_integer(line) and line > 0 -> port_options ++ [line: line]
      _line -> port_options
    end
  end

  defp normalize_signal_arg("-" <> _ = signal), do: signal
  defp normalize_signal_arg(signal), do: "-#{signal}"

  defp non_negative_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value >= 0 -> value
      _value -> default
    end
  end

  defp positive_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      _value -> default
    end
  end
end
