defmodule SymphonyElixir.AgentProvider.ClaudeCode.AppServer.Launcher do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context, as: DynamicToolContext
  alias SymphonyElixir.Agent.Runtime.{CommandSpec, DynamicToolBridge, Environment, Target}
  alias SymphonyElixir.AgentProvider.ClaudeCode.{Settings, Tooling}
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.PathSafety
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Workspace.AutomationPack

  @port_line_bytes 1_048_576
  @provider_kind Kinds.claude_code()

  @spec validate_runtime_placement(keyword()) :: :ok | {:error, term()}
  def validate_runtime_placement(_opts), do: :ok

  @spec validate_workspace_cwd(Path.t(), String.t() | nil) :: {:ok, Path.t()} | {:error, term()}
  def validate_workspace_cwd(workspace, nil) when is_binary(workspace) do
    expanded_workspace = Path.expand(workspace)

    case PathSafety.canonicalize(expanded_workspace) do
      {:ok, canonical_workspace} ->
        {:ok, canonical_workspace}

      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  def validate_workspace_cwd(workspace, worker_host) when is_binary(workspace) and is_binary(worker_host) do
    cond do
      String.trim(workspace) == "" ->
        {:error, {:invalid_workspace_cwd, :empty_remote_workspace, worker_host}}

      String.contains?(workspace, ["\n", "\r", <<0>>]) ->
        {:error, {:invalid_workspace_cwd, :invalid_remote_workspace, worker_host, workspace}}

      true ->
        {:ok, workspace}
    end
  end

  @spec start_port(Path.t(), Settings.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def start_port(workspace, %Settings{} = settings, session_id, opts) when is_binary(session_id) do
    opts = Keyword.put(opts, :session_id, session_id)

    with {:ok, env, bridge_env} <- runtime_env(settings, workspace, opts) do
      target = runtime_target(workspace, opts)

      with :ok <- maybe_write_runtime_mcp_config(workspace, target, opts, bridge_env) do
        command_spec = command_spec(workspace, target, settings, session_id, env, opts)

        target.executor.start(command_spec, target, executor_opts(opts))
      end
    end
  end

  @spec runtime_worker_host(keyword()) :: String.t() | nil
  def runtime_worker_host(opts) when is_list(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{worker_host: worker_host} when is_binary(worker_host) -> worker_host
      _target -> Keyword.get(opts, :worker_host)
    end
  end

  defp command_spec(workspace, %Target{placement: :ssh}, %Settings{} = settings, session_id, env, opts) do
    CommandSpec.new(command: remote_launch_command(workspace, settings, session_id, env, opts), cwd: workspace)
  end

  defp command_spec(workspace, %Target{}, %Settings{} = settings, session_id, env, opts) do
    case Settings.command_argv(settings) do
      argv when is_list(argv) ->
        CommandSpec.new(argv: argv ++ claude_args(settings, session_id, opts), env: env, cwd: workspace)

      nil ->
        CommandSpec.new(command: shell_launch_command(settings, session_id, opts), env: env, cwd: workspace)
    end
  end

  defp runtime_target(workspace, opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{} = target -> %{target | workspace_path: workspace}
      _target -> Target.new(workspace_path: workspace, worker_host: Keyword.get(opts, :worker_host))
    end
  end

  defp executor_opts(opts) do
    opts
    |> Keyword.put(:line, @port_line_bytes)
    |> Keyword.put_new(:provider_kind, @provider_kind)
  end

  defp claude_args(%Settings{} = settings, session_id, opts) when is_binary(session_id) and is_list(opts) do
    [
      "-p",
      "--output-format",
      "stream-json",
      "--input-format",
      "stream-json",
      "--verbose",
      "--strict-mcp-config",
      "--mcp-config",
      Tooling.mcp_config_relative_path(),
      "--session-id",
      session_id,
      "--permission-mode",
      settings.permission_mode
    ]
    |> maybe_append_model(settings.model)
    |> maybe_append_effort(settings.effort)
    |> maybe_append_allowed_mcp_tools(settings, opts)
  end

  defp shell_launch_command(%Settings{} = settings, session_id, opts) do
    ([settings.command] ++ Enum.map(claude_args(settings, session_id, opts), &shell_escape/1))
    |> Enum.join(" ")
  end

  defp remote_launch_command(workspace, %Settings{} = settings, session_id, env, opts) do
    (remote_environment_exports(env) ++
       [
         "cd #{shell_escape(workspace)}",
         "exec #{remote_exec_command(settings, session_id, opts)}"
       ])
    |> Enum.join(" && ")
  end

  defp remote_exec_command(%Settings{} = settings, session_id, opts) do
    case Settings.command_argv(settings) do
      argv when is_list(argv) -> shell_join(argv ++ claude_args(settings, session_id, opts))
      nil -> shell_launch_command(settings, session_id, opts)
    end
  end

  defp remote_environment_exports(env) when is_map(env) do
    env
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.map(fn {key, value} -> "export #{key}=#{shell_escape(to_string(value))}" end)
  end

  defp runtime_env(%Settings{} = settings, workspace, opts) do
    with {:ok, env} <- Environment.current_env(@provider_kind, settings.telemetry, Keyword.put(opts, :include_dynamic_tool_env, false)),
         {:ok, bridge_env} <- DynamicToolBridge.runtime_env(opts) do
      provider_env =
        RepoProvider.runtime_env()
        |> Kernel.++(AutomationPack.runtime_env(workspace, ".claude"))
        |> Map.new()

      {:ok, env |> Map.merge(bridge_env) |> Map.merge(provider_env) |> Map.merge(settings.env), bridge_env_for_mcp(opts, bridge_env)}
    end
  end

  defp bridge_env_for_mcp(opts, bridge_env) when is_list(opts) and is_map(bridge_env) do
    case Keyword.get(opts, :dynamic_tool_bridge_runtime) do
      %{daemon_bridge: %{"provider_env" => provider_env}} when is_map(provider_env) -> provider_env
      _runtime -> bridge_env
    end
  end

  defp maybe_write_runtime_mcp_config(workspace, %Target{placement: :local}, opts, bridge_env) do
    Tooling.write_runtime_mcp_config(workspace, opts, bridge_env)
  end

  defp maybe_write_runtime_mcp_config(_workspace, %Target{}, _opts, _bridge_env), do: :ok

  defp maybe_append_model(parts, model) when is_binary(model) and model != "", do: parts ++ ["--model", model]
  defp maybe_append_model(parts, _model), do: parts

  defp maybe_append_effort(parts, effort) when is_binary(effort) and effort != "", do: parts ++ ["--effort", effort]
  defp maybe_append_effort(parts, _effort), do: parts

  defp maybe_append_allowed_mcp_tools(parts, %Settings{} = settings, opts) do
    cond do
      allowed_tools_configured?(settings) ->
        parts

      mcp_tool_names = allowed_mcp_tool_names(opts) ->
        parts ++ ["--allowedTools", Enum.join(mcp_tool_names, ",")]

      true ->
        parts
    end
  end

  defp allowed_tools_configured?(%Settings{} = settings) do
    argv =
      case Settings.command_argv(settings) do
        argv when is_list(argv) -> argv
        nil -> [settings.command || ""]
      end

    Enum.any?(argv, fn arg ->
      String.starts_with?(arg, "--allowedTools") or String.starts_with?(arg, "--allowed-tools")
    end)
  end

  defp allowed_mcp_tool_names(opts) when is_list(opts) do
    opts
    |> DynamicToolContext.from_opts()
    |> DynamicToolContext.tool_specs()
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) and name != "" -> [Tooling.mcp_tool_name(name)]
      _tool -> []
    end)
    |> Enum.uniq()
    |> case do
      [] -> nil
      names -> names
    end
  end

  defp shell_escape(value) when is_binary(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"

  defp shell_join(argv) when is_list(argv), do: Enum.map_join(argv, " ", &shell_escape/1)
end
