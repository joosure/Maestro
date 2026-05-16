defmodule SymphonyElixir.Platform.SSH do
  @moduledoc false

  alias SymphonyElixir.Platform.CommandEnv

  @ssh_config_env "SYMPHONY_SSH_CONFIG"
  @ssh_known_hosts_env "SYMPHONY_SSH_KNOWN_HOSTS"
  @non_interactive_args [
    "-o",
    "BatchMode=yes",
    "-o",
    "NumberOfPasswordPrompts=0",
    "-o",
    "KbdInteractiveAuthentication=no"
  ]
  @host_key_verification_args ["-o", "StrictHostKeyChecking=yes"]
  @ssh_user_pattern ~r/^[A-Za-z0-9._-]+$/
  @ssh_host_pattern ~r/^[A-Za-z0-9._-]+$/

  @spec run(String.t(), String.t(), keyword()) :: {:ok, {String.t(), non_neg_integer()}} | {:error, term()}
  def run(host, command, opts \\ []) when is_binary(host) and is_binary(command) do
    with {:ok, normalized_host} <- normalize_host_entry(host),
         {:ok, executable} <- ssh_executable() do
      {:ok, CommandEnv.system_cmd(executable, ssh_args(normalized_host, command), opts)}
    end
  end

  @spec copy_dir(String.t(), Path.t(), Path.t(), keyword()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, term()}
  def copy_dir(host, source_dir, remote_parent_dir, opts \\ [])
      when is_binary(host) and is_binary(source_dir) and is_binary(remote_parent_dir) do
    with {:ok, normalized_host} <- normalize_host_entry(host),
         {:ok, executable} <- scp_executable() do
      {:ok, CommandEnv.system_cmd(executable, scp_args(normalized_host, source_dir, remote_parent_dir), opts)}
    end
  end

  @spec start_port(String.t(), String.t(), keyword()) :: {:ok, port()} | {:error, term()}
  def start_port(host, command, opts \\ []) when is_binary(host) and is_binary(command) do
    with {:ok, normalized_host} <- normalize_host_entry(host),
         {:ok, executable} <- ssh_executable() do
      line_bytes = Keyword.get(opts, :line)

      port_opts =
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: Enum.map(ssh_args(normalized_host, command), &String.to_charlist/1)
        ]
        |> maybe_put_line_option(line_bytes)

      {:ok, Port.open({:spawn_executable, String.to_charlist(executable)}, port_opts)}
    end
  end

  @spec start_remote_port_forward(String.t(), pos_integer(), String.t(), pos_integer(), keyword()) ::
          {:ok, port()} | {:error, term()}
  def start_remote_port_forward(host, remote_port, local_host, local_port, _opts \\ [])
      when is_binary(host) and is_binary(local_host) and is_integer(remote_port) and is_integer(local_port) do
    with :ok <- validate_forward_port(remote_port),
         :ok <- validate_forward_port(local_port),
         :ok <- validate_forward_host(local_host),
         {:ok, normalized_host} <- normalize_host_entry(host),
         {:ok, executable} <- ssh_executable() do
      port_opts = [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args:
          normalized_host
          |> ssh_remote_forward_args(remote_port, local_host, local_port)
          |> Enum.map(&String.to_charlist/1)
      ]

      {:ok, Port.open({:spawn_executable, String.to_charlist(executable)}, port_opts)}
    end
  end

  @spec remote_shell_command(String.t()) :: String.t()
  def remote_shell_command(command) when is_binary(command) do
    "bash -lc " <> shell_escape(command)
  end

  @spec normalize_host_entry(term()) :: {:ok, String.t()} | {:error, atom()}
  def normalize_host_entry(host)

  def normalize_host_entry(host) when not is_binary(host), do: {:error, :not_a_string}

  def normalize_host_entry(host) when is_binary(host) do
    trimmed_host = String.trim(host)

    cond do
      trimmed_host == "" ->
        {:error, :blank}

      String.contains?(trimmed_host, ["\n", "\r", "\t", <<0>>]) ->
        {:error, :invalid_characters}

      String.match?(trimmed_host, ~r/\s/u) ->
        {:error, :contains_whitespace}

      invalid_bracket_target?(trimmed_host) ->
        {:error, :invalid_brackets}

      true ->
        with {:ok, {user_prefix, destination_part}} <- split_user_prefix(trimmed_host),
             {:ok, %{host: normalized_host, port: port}} <- normalize_destination_part(destination_part),
             {:ok, normalized_port} <- normalize_port(port) do
          {:ok, normalize_target_string(user_prefix <> normalized_host, normalized_port)}
        end
    end
  end

  defp ssh_executable do
    case System.find_executable("ssh") do
      nil -> {:error, :ssh_not_found}
      executable -> {:ok, executable}
    end
  end

  defp scp_executable do
    case System.find_executable("scp") do
      nil -> {:error, :scp_not_found}
      executable -> {:ok, executable}
    end
  end

  defp ssh_args(host, command) do
    %{destination: destination, port: port} = parse_target(host)

    []
    |> put_common_ssh_options()
    |> Kernel.++(["-T"])
    |> maybe_put_port(port)
    |> Kernel.++([destination, remote_shell_command(command)])
  end

  defp ssh_remote_forward_args(host, remote_port, local_host, local_port) do
    %{destination: destination, port: port} = parse_target(host)
    forward_spec = "127.0.0.1:#{remote_port}:#{local_host}:#{local_port}"

    []
    |> put_common_ssh_options()
    |> Kernel.++(["-o", "ExitOnForwardFailure=yes", "-N", "-T"])
    |> maybe_put_port(port)
    |> Kernel.++(["-R", forward_spec, destination])
  end

  defp scp_args(host, source_dir, remote_parent_dir) do
    %{destination: destination, port: port} = parse_target(host)

    remote_target = destination <> ":" <> remote_parent_dir

    []
    |> put_common_ssh_options()
    |> maybe_put_scp_port(port)
    |> Kernel.++(["-r", source_dir, remote_target])
  end

  defp parse_target(target) when is_binary(target) do
    trimmed_target = String.trim(target)

    # OpenSSH does not interpret bare "host:port" as "host + port"; it treats the
    # whole value as a hostname and leaves the port at 22. We split that shorthand
    # here so worker config can use "localhost:2222" without requiring ssh:// URIs.
    case Regex.run(~r/^(.*):(\d+)$/, trimmed_target, capture: :all_but_first) do
      [destination, port] ->
        if valid_port_destination?(destination) do
          %{destination: destination, port: port}
        else
          %{destination: trimmed_target, port: nil}
        end

      _ ->
        %{destination: trimmed_target, port: nil}
    end
  end

  defp maybe_put_line_option(port_opts, nil), do: port_opts
  defp maybe_put_line_option(port_opts, line_bytes), do: port_opts ++ [line: line_bytes]

  defp put_common_ssh_options(args) do
    args
    |> maybe_put_config()
    |> maybe_put_known_hosts()
    |> Kernel.++(@non_interactive_args)
    |> Kernel.++(@host_key_verification_args)
  end

  defp maybe_put_config(args) do
    case System.get_env(@ssh_config_env) do
      config_path when is_binary(config_path) and config_path != "" ->
        args ++ ["-F", config_path]

      _ ->
        args
    end
  end

  defp maybe_put_known_hosts(args) do
    case System.get_env(@ssh_known_hosts_env) do
      known_hosts_path when is_binary(known_hosts_path) and known_hosts_path != "" ->
        args ++ ["-o", "UserKnownHostsFile=#{known_hosts_path}"]

      _ ->
        args
    end
  end

  defp maybe_put_port(args, nil), do: args
  defp maybe_put_port(args, port), do: args ++ ["-p", port]
  defp maybe_put_scp_port(args, nil), do: args
  defp maybe_put_scp_port(args, port), do: args ++ ["-P", port]

  defp validate_forward_port(port) when is_integer(port) and port in 1..65_535, do: :ok
  defp validate_forward_port(_port), do: {:error, :invalid_forward_port}

  defp validate_forward_host(host) when is_binary(host) do
    cond do
      String.trim(host) == "" -> {:error, :invalid_forward_host}
      String.contains?(host, ["\n", "\r", "\t", <<0>>]) -> {:error, :invalid_forward_host}
      String.match?(host, ~r/\s/u) -> {:error, :invalid_forward_host}
      true -> :ok
    end
  end

  defp valid_port_destination?(destination) when is_binary(destination) do
    destination != "" and
      (not String.contains?(destination, ":") or bracketed_host?(destination))
  end

  defp bracketed_host?(destination) when is_binary(destination) do
    # IPv6 literals contain ":" already, so we only accept additional ":port"
    # parsing when the host is explicitly bracketed, e.g. "[::1]:2222".
    String.contains?(destination, "[") and String.contains?(destination, "]")
  end

  defp invalid_bracket_target?(target) when is_binary(target) do
    left_brackets = String.graphemes(target) |> Enum.count(&(&1 == "["))
    right_brackets = String.graphemes(target) |> Enum.count(&(&1 == "]"))

    left_brackets != right_brackets or
      (String.contains?(target, "[") and not String.contains?(target, "]")) or
      (String.contains?(target, "]") and not String.contains?(target, "["))
  end

  defp split_user_prefix(target) when is_binary(target) do
    case String.split(target, "@", parts: 2) do
      [destination_part] ->
        {:ok, {"", destination_part}}

      [user, destination_part] ->
        cond do
          user == "" or destination_part == "" ->
            {:error, :invalid_destination}

          String.contains?(destination_part, "@") ->
            {:error, :invalid_destination}

          not Regex.match?(@ssh_user_pattern, user) ->
            {:error, :invalid_destination}

          true ->
            {:ok, {user <> "@", destination_part}}
        end
    end
  end

  defp normalize_destination_part(destination_part) when is_binary(destination_part) do
    cond do
      String.contains?(destination_part, "://") ->
        {:error, :invalid_destination}

      String.starts_with?(destination_part, "[") ->
        normalize_bracketed_destination(destination_part)

      String.contains?(destination_part, ":") ->
        normalize_host_with_optional_port(destination_part)

      Regex.match?(@ssh_host_pattern, destination_part) ->
        {:ok, %{host: destination_part, port: nil}}

      true ->
        {:error, :invalid_destination}
    end
  end

  defp normalize_bracketed_destination(destination_part) when is_binary(destination_part) do
    case Regex.run(~r/^\[([^\]]+)\](?::(\d+))?$/, destination_part, capture: :all_but_first) do
      [host] ->
        validate_bracketed_ipv6_literal(host, nil)

      [host, port] ->
        validate_bracketed_ipv6_literal(host, port)

      _ ->
        {:error, :invalid_destination}
    end
  end

  defp normalize_host_with_optional_port(destination_part) when is_binary(destination_part) do
    colon_count = String.graphemes(destination_part) |> Enum.count(&(&1 == ":"))

    cond do
      colon_count == 1 ->
        case String.split(destination_part, ":", parts: 2) do
          [host, port] when host != "" and port != "" ->
            cond do
              not Regex.match?(@ssh_host_pattern, host) ->
                {:error, :invalid_destination}

              not String.match?(port, ~r/^\d+$/) ->
                {:error, :invalid_port_target}

              true ->
                {:ok, %{host: host, port: port}}
            end

          _ ->
            {:error, :invalid_port_target}
        end

      true ->
        {:error, :invalid_destination}
    end
  end

  defp validate_bracketed_ipv6_literal(host, port) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} when tuple_size(address) == 8 ->
        {:ok, %{host: "[" <> host <> "]", port: port}}

      _ ->
        {:error, :invalid_destination}
    end
  end

  defp normalize_port(nil), do: {:ok, nil}

  defp normalize_port(port) when is_binary(port) do
    with {port_number, ""} <- Integer.parse(port),
         true <- port_number > 0 and port_number <= 65_535 do
      {:ok, Integer.to_string(port_number)}
    else
      _ -> {:error, :invalid_port}
    end
  end

  defp normalize_target_string(destination, nil), do: destination
  defp normalize_target_string(destination, port), do: destination <> ":" <> port

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
