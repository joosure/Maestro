defmodule SymphonyElixir.AgentProvider.Codex.AppServer.Launcher do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, DynamicToolBridge, Environment, Target}
  alias SymphonyElixir.AgentProvider.Codex.Credential, as: CodexCredential
  alias SymphonyElixir.AgentProvider.Codex.Settings, as: CodexSettings
  alias SymphonyElixir.AgentProvider.Codex.Tooling
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.PathSafety
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Workspace.AutomationPack
  alias SymphonyElixir.Workspace.Paths, as: WorkspacePaths
  alias SymphonyElixir.Workspace.Remote, as: WorkspaceRemote

  @port_line_bytes 1_048_576
  @env_name_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/
  @provider_kind Kinds.codex()

  @spec validate_workspace_cwd(Path.t(), String.t() | nil, map()) :: {:ok, Path.t()} | {:error, term()}
  def validate_workspace_cwd(workspace, nil, runtime_context) when is_binary(workspace) do
    with {:ok, workspace_root} <- runtime_workspace_root(runtime_context) do
      validate_local_workspace_cwd(workspace, workspace_root)
    end
  end

  def validate_workspace_cwd(workspace, worker_host, runtime_context)
      when is_binary(workspace) and is_binary(worker_host) do
    cond do
      String.trim(workspace) == "" ->
        {:error, {:invalid_workspace_cwd, :empty_remote_workspace, worker_host}}

      String.contains?(workspace, ["\n", "\r", <<0>>]) ->
        {:error, {:invalid_workspace_cwd, :invalid_remote_workspace, worker_host, workspace}}

      true ->
        with {:ok, workspace_root} <- runtime_workspace_root(runtime_context),
             {:ok, hook_timeout_ms} <- runtime_hook_timeout_ms(runtime_context) do
          WorkspacePaths.validate_remote_workspace_boundary(
            workspace,
            worker_host,
            workspace_root,
            WorkspaceRemote.remote_command_runner(worker_host, hook_timeout_ms)
          )
        end
        |> case do
          {:ok, canonical_workspace} ->
            {:ok, canonical_workspace}

          {:error, {:workspace_equals_root, path, _root}} ->
            {:error, {:invalid_workspace_cwd, :workspace_root, path}}

          {:error, {:workspace_outside_root, path, root}} ->
            {:error, {:invalid_workspace_cwd, :outside_workspace_root, path, root}}

          {:error, {:workspace_path_unreadable, path, reason}} ->
            {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}

          {:error, {:invalid_workspace_cwd, _reason} = reason} ->
            {:error, reason}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @spec start_port(Path.t(), String.t() | nil, CodexSettings.t(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def start_port(workspace, worker_host, %CodexSettings{} = codex_settings, runtime_context, opts) do
    target = runtime_target(workspace, worker_host, runtime_context)

    with {:ok, command_spec} <- command_spec(workspace, target, codex_settings, opts) do
      target.executor.start(
        command_spec,
        target,
        executor_opts(runtime_context)
      )
    end
  end

  defp validate_local_workspace_cwd(workspace, workspace_root)
       when is_binary(workspace) and is_binary(workspace_root) do
    expanded_workspace = Path.expand(workspace)
    expanded_root = Path.expand(workspace_root)
    expanded_root_prefix = expanded_root <> "/"

    with {:ok, canonical_workspace} <- PathSafety.canonicalize(expanded_workspace),
         {:ok, canonical_root} <- PathSafety.canonicalize(expanded_root) do
      canonical_root_prefix = canonical_root <> "/"

      cond do
        canonical_workspace == canonical_root ->
          {:error, {:invalid_workspace_cwd, :workspace_root, canonical_workspace}}

        String.starts_with?(canonical_workspace <> "/", canonical_root_prefix) ->
          {:ok, canonical_workspace}

        String.starts_with?(expanded_workspace <> "/", expanded_root_prefix) ->
          {:error, {:invalid_workspace_cwd, :symlink_escape, expanded_workspace, canonical_root}}

        true ->
          {:error, {:invalid_workspace_cwd, :outside_workspace_root, canonical_workspace, canonical_root}}
      end
    else
      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  defp opts_from_runtime_context(%{executor_opts: executor_opts}) when is_list(executor_opts), do: executor_opts
  defp opts_from_runtime_context(%{"executor_opts" => executor_opts}) when is_list(executor_opts), do: executor_opts
  defp opts_from_runtime_context(_runtime_context), do: []

  defp executor_opts(runtime_context) do
    runtime_context
    |> opts_from_runtime_context()
    |> Keyword.put(:line, @port_line_bytes)
    |> Keyword.put_new(:provider_kind, @provider_kind)
  end

  defp runtime_target(workspace, worker_host, runtime_context) when is_map(runtime_context) do
    case Map.get(runtime_context, :agent_runtime_target) || Map.get(runtime_context, "agent_runtime_target") do
      %Target{} = target -> %{target | workspace_path: workspace, worker_host: worker_host || target.worker_host}
      _target -> Target.new(workspace_path: workspace, worker_host: worker_host)
    end
  end

  defp command_spec(workspace, %Target{placement: :ssh}, %CodexSettings{} = codex_settings, opts) do
    with {:ok, env} <- local_session_env(workspace, opts),
         {:ok, session_exports} <- remote_session_exports_from_env(env) do
      {setup_commands, cleanup_commands} =
        CodexCredential.remote_auth_commands(Keyword.get(opts, :agent_credential_material))

      setup_commands = setup_commands ++ Tooling.remote_setup_commands(workspace, opts)

      {:ok,
       CommandSpec.new(
         command: remote_launch_command(workspace, codex_settings, session_exports, setup_commands, cleanup_commands, opts),
         cwd: workspace
       )}
    end
  end

  defp command_spec(workspace, %Target{placement: :worker_daemon}, %CodexSettings{} = codex_settings, opts) do
    with {:ok, env} <- local_session_env(workspace, opts) do
      {setup_commands, cleanup_commands} =
        CodexCredential.remote_auth_commands(Keyword.get(opts, :agent_credential_material))

      setup_commands = setup_commands ++ Tooling.remote_setup_commands(workspace, opts)

      command_spec =
        case setup_commands do
          [] ->
            local_command_spec(workspace, codex_settings, env, opts)

          _commands ->
            CommandSpec.new(
              argv: ["sh", "-lc", remote_wrapped_command(workspace, codex_settings, setup_commands, cleanup_commands, opts)],
              cwd: workspace,
              env: env
            )
        end

      {:ok, command_spec}
    end
  end

  defp command_spec(workspace, %Target{}, %CodexSettings{} = codex_settings, opts) do
    with :ok <- Tooling.write_runtime_mcp_server(workspace, opts),
         {:ok, env} <- local_session_env(workspace, opts) do
      {:ok, local_command_spec(workspace, codex_settings, env, opts)}
    end
  end

  defp local_command_spec(workspace, %CodexSettings{} = codex_settings, env, opts)
       when is_binary(workspace) and is_map(env) do
    mcp_args = Tooling.mcp_config_args(opts)

    case CodexSettings.command_argv(codex_settings) do
      argv when is_list(argv) -> CommandSpec.new(argv: argv ++ mcp_args, cwd: workspace, env: env)
      nil -> CommandSpec.new(command: append_command_args(codex_settings.command, mcp_args), cwd: workspace, env: env)
    end
  end

  defp remote_launch_command(workspace, codex_settings, session_exports, [], [], opts)
       when is_binary(workspace) and is_list(session_exports) do
    (session_exports ++ ["cd #{shell_escape(workspace)}", remote_exec_command(codex_settings, opts)])
    |> Enum.join(" && ")
  end

  defp remote_launch_command(workspace, codex_settings, session_exports, setup_commands, cleanup_commands, opts)
       when is_binary(workspace) and is_list(session_exports) and is_list(setup_commands) and
              is_list(cleanup_commands) do
    setup_prefix =
      (setup_commands ++ session_exports ++ ["cd #{shell_escape(workspace)}"])
      |> Enum.join(" && ")

    "#{cleanup_traps(cleanup_commands)}; #{setup_prefix} && #{remote_run_command(codex_settings, opts)}; status=$?; exit $status"
  end

  defp remote_wrapped_command(workspace, codex_settings, setup_commands, cleanup_commands, opts)
       when is_binary(workspace) and is_list(setup_commands) and is_list(cleanup_commands) do
    setup_prefix =
      (setup_commands ++ ["cd #{shell_escape(workspace)}"])
      |> Enum.join(" && ")

    "#{cleanup_traps(cleanup_commands)}; #{setup_prefix} && #{remote_run_command(codex_settings, opts)}; status=$?; exit $status"
  end

  defp remote_exec_command(%CodexSettings{} = codex_settings, opts) do
    mcp_args = Tooling.mcp_config_args(opts)

    case CodexSettings.command_argv(codex_settings) do
      argv when is_list(argv) -> "exec #{shell_join(argv ++ mcp_args)}"
      nil -> "exec #{append_command_args(codex_settings.command, mcp_args)}"
    end
  end

  defp remote_run_command(%CodexSettings{} = codex_settings, opts) do
    mcp_args = Tooling.mcp_config_args(opts)

    case CodexSettings.command_argv(codex_settings) do
      argv when is_list(argv) -> shell_join(argv ++ mcp_args)
      nil -> append_command_args(codex_settings.command, mcp_args)
    end
  end

  defp cleanup_command([]), do: ":"
  defp cleanup_command(cleanup_commands) when is_list(cleanup_commands), do: Enum.join(cleanup_commands, "; ")

  defp cleanup_traps(cleanup_commands) do
    cleanup = cleanup_command(cleanup_commands)
    signal_cleanup = cleanup <> "; trap - EXIT HUP INT TERM; exit 143"

    [
      "trap #{shell_escape(cleanup)} EXIT",
      "trap #{shell_escape(signal_cleanup)} HUP INT TERM"
    ]
    |> Enum.join("; ")
  end

  defp runtime_workspace_root(runtime_context) when is_map(runtime_context) do
    case Map.get(runtime_context, :workspace_root) || Map.get(runtime_context, "workspace_root") do
      root when is_binary(root) and root != "" -> {:ok, root}
      other -> {:error, {:invalid_workspace_cwd, {:missing_workspace_root, other}}}
    end
  end

  defp runtime_hook_timeout_ms(runtime_context) when is_map(runtime_context) do
    case Map.get(runtime_context, :hook_timeout_ms) || Map.get(runtime_context, "hook_timeout_ms") do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 ->
        {:ok, timeout_ms}

      other ->
        {:error, {:invalid_workspace_cwd, {:missing_hook_timeout_ms, other}}}
    end
  end

  defp local_session_env(workspace, opts) when is_binary(workspace) and is_list(opts) do
    with {:ok, common_env} <- provider_process_env(opts),
         {:ok, bridge_env} <- DynamicToolBridge.runtime_env(opts) do
      {:ok, common_env |> Map.merge(bridge_env) |> Map.merge(codex_session_env(workspace))}
    end
  end

  defp provider_process_env(opts) when is_list(opts) do
    Environment.current_env(@provider_kind, %{}, Keyword.put(opts, :include_dynamic_tool_env, false))
  end

  defp codex_session_env(workspace) when is_binary(workspace) do
    RepoProvider.runtime_env()
    |> Kernel.++(AutomationPack.runtime_env(workspace, ".codex"))
    |> Map.new()
  end

  defp remote_session_exports_from_env(env) when is_map(env) do
    Enum.reduce_while(env, {:ok, []}, fn entry, {:ok, exports} ->
      case remote_session_export(entry) do
        {:ok, export} -> {:cont, {:ok, [export | exports]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, exports} -> {:ok, Enum.reverse(exports)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp remote_session_export({key, value}) do
    key = to_string(key)

    if Regex.match?(@env_name_pattern, key) do
      {:ok, remote_session_export_value(key, value)}
    else
      {:error, {:invalid_remote_env_name, key}}
    end
  end

  defp remote_session_export_value(key, nil), do: "unset #{key}"
  defp remote_session_export_value(key, value), do: "export #{key}=#{shell_escape(to_string(value))}"

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp append_command_args(command, []) when is_binary(command), do: command
  defp append_command_args(command, args) when is_binary(command) and is_list(args), do: command <> " " <> shell_join(args)

  defp shell_join(argv) when is_list(argv), do: Enum.map_join(argv, " ", &shell_escape/1)
end
