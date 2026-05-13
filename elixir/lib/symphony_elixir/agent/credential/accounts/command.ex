defmodule SymphonyElixir.Agent.Credential.Accounts.Command do
  @moduledoc false

  alias SymphonyElixir.Observability.Redaction

  @secret_mode 0o600

  @spec run(String.t(), [String.t()], [{String.t(), term()}], keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(command, args, env, opts) do
    command_parts = shell_words(command)

    case command_parts do
      [] ->
        {:error, :missing_provider_command}

      [executable | command_args] ->
        args = command_args ++ args
        env = Enum.map(env, fn {key, value} -> {key, to_string(value)} end)

        case Keyword.get(opts, :runner) do
          runner when is_function(runner, 4) ->
            runner.(executable, args, env, opts)

          _runner ->
            run_provider_command(executable, args, env, opts)
        end
    end
  rescue
    error -> {:error, error}
  end

  defp run_provider_command(executable, args, env, opts) do
    cond do
      Keyword.get(opts, :tty_capture, false) ->
        run_provider_tty_capture(executable, args, env, opts)

      Keyword.get(opts, :stream, false) ->
        run_provider_stream(executable, args, env)

      true ->
        case System.cmd(executable, args, env: env, stderr_to_stdout: true) do
          {output, 0} -> {:ok, IO.iodata_to_binary(output)}
          {output, status} -> {:error, %{exit_status: status, output: redact_sensitive(output)}}
        end
    end
  end

  defp run_provider_tty_capture(executable, args, env, opts) do
    with {:ok, executable_path} <- resolve_executable(executable),
         {:ok, script_path} <- resolve_executable("script"),
         {:ok, transcript_path} <- prepare_transcript_path(opts) do
      command = script_shell_command(script_path, transcript_path, executable_path, args)

      {shell_output, status} =
        System.cmd("/bin/sh", ["-lc", command],
          env: env,
          stderr_to_stdout: true
        )

      transcript = read_transcript(transcript_path)
      File.rm(transcript_path)
      output = transcript <> IO.iodata_to_binary(shell_output)

      case status do
        0 -> {:ok, output}
        _status -> {:error, %{exit_status: status, output: redact_sensitive(output)}}
      end
    end
  end

  defp run_provider_stream(executable, args, env) do
    with {:ok, executable_path} <- resolve_executable(executable) do
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(executable_path)},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: Enum.map(args, &String.to_charlist/1),
            env: Enum.map(env, fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
          ]
        )

      receive_provider_stream(port, [])
    end
  end

  defp prepare_transcript_path(opts) do
    path =
      Keyword.get(opts, :transcript_path) ||
        Path.join(System.tmp_dir!(), "symphony-claude-setup-token-#{System.unique_integer([:positive])}.log")

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, ""),
         :ok <- File.chmod(path, @secret_mode) do
      {:ok, path}
    end
  end

  defp script_shell_command(script_path, transcript_path, executable_path, args) do
    command =
      case :os.type() do
        {:unix, :darwin} ->
          shell_join([script_path, "-q", transcript_path, executable_path | args])

        _os_type ->
          shell_join([script_path, "-q", "-c", shell_join([executable_path | args]), transcript_path])
      end

    command <> " </dev/tty >/dev/tty 2>&1"
  end

  defp read_transcript(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      _error -> ""
    end
  end

  defp receive_provider_stream(port, chunks) do
    receive do
      {^port, {:data, data}} ->
        IO.write(sanitize_interactive_output(data))
        receive_provider_stream(port, [data | chunks])

      {^port, {:exit_status, 0}} ->
        {:ok, IO.iodata_to_binary(Enum.reverse(chunks))}

      {^port, {:exit_status, status}} ->
        output = IO.iodata_to_binary(Enum.reverse(chunks))
        {:error, %{exit_status: status, output: redact_sensitive(output)}}
    end
  end

  defp resolve_executable(executable) do
    cond do
      String.contains?(executable, "/") and File.exists?(executable) ->
        {:ok, executable}

      executable_path = System.find_executable(executable) ->
        {:ok, executable_path}

      true ->
        {:error, {:provider_command_not_found, executable}}
    end
  end

  defp shell_words(command) when is_binary(command), do: String.split(command, ~r/\s+/, trim: true)

  defp shell_join(parts), do: Enum.map_join(parts, " ", &shell_quote/1)

  defp shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"
  end

  defp sanitize_interactive_output(data) when is_binary(data) do
    data
    |> String.replace("\e[?2004h", "")
    |> String.replace("\e[?2004l", "")
  end

  defp redact_sensitive(output) do
    output
    |> IO.iodata_to_binary()
    |> Redaction.redact_string()
    |> String.slice(0, 4_000)
  end
end
