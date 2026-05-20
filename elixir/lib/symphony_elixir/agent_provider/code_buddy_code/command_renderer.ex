defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.CommandRenderer do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.CommandSpec
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.Settings

  @stdio_owned_conflict_flags ~w(--serve --host --port --mcp-config --strict-mcp-config --plugin-dir --dangerously-load-development-channels -y --dangerously-skip-permissions)
  @http_owned_conflict_flags ~w(--serve --host --port --acp --acp-transport --mcp-config --strict-mcp-config --plugin-dir --dangerously-load-development-channels -y --dangerously-skip-permissions)
  @single_source_flags ~w(--permission-mode --tools --allowedTools --disallowedTools --model --agent)

  @spec command_spec(Path.t(), Settings.t(), map()) :: {:ok, CommandSpec.t()} | {:error, term()}
  def command_spec(workspace, settings, env, opts \\ [])

  @spec command_spec(Path.t(), Settings.t(), map(), keyword()) :: {:ok, CommandSpec.t()} | {:error, term()}
  def command_spec(workspace, %Settings{} = settings, env, opts) when is_binary(workspace) and is_map(env) and is_list(opts) do
    with {:ok, args} <- rendered_args(settings, opts) do
      case Settings.command_argv(settings) do
        argv when is_list(argv) ->
          {:ok, CommandSpec.new(argv: argv ++ args, cwd: workspace, env: env, metadata: command_metadata(settings, args, opts))}

        nil ->
          {:ok,
           CommandSpec.new(
             command: append_command_args(settings.command, args),
             cwd: workspace,
             env: env,
             metadata: command_metadata(settings, args, opts)
           )}
      end
    end
  end

  @spec rendered_argv(Settings.t()) :: {:ok, [String.t()]} | {:error, term()}
  def rendered_argv(settings, opts \\ [])

  @spec rendered_argv(Settings.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def rendered_argv(%Settings{} = settings, opts) when is_list(opts) do
    with {:ok, args} <- rendered_args(settings, opts) do
      case Settings.command_argv(settings) do
        argv when is_list(argv) -> {:ok, argv ++ args}
        nil -> {:error, :command_string_configured}
      end
    end
  end

  defp rendered_args(%Settings{transport: "acp_stdio"} = settings, opts) do
    with :ok <- validate_command_conflicts(settings) do
      tooling_runtime = Keyword.get(opts, :codebuddy_code_tooling_runtime)

      {:ok,
       []
       |> maybe_append_acp(settings)
       |> maybe_append_acp_transport(settings)
       |> append_runtime_mcp_args(tooling_runtime)
       |> append_permission_args(settings, tooling_runtime)
       |> maybe_append_setting_sources(settings)
       |> maybe_append_pair("--model", settings.model)
       |> maybe_append_pair("--agent", settings.agent)
       |> maybe_append_tools("--allowedTools", effective_allowed_tools(settings, tooling_runtime))
       |> maybe_append_tools("--disallowedTools", settings.disallowed_tools)}
    end
  end

  defp rendered_args(%Settings{transport: "acp_http"} = settings, opts) do
    with :ok <- validate_command_conflicts(settings) do
      tooling_runtime = Keyword.get(opts, :codebuddy_code_tooling_runtime)

      {:ok,
       []
       |> append_http_service_args(settings)
       |> append_permission_args(settings, tooling_runtime)
       |> maybe_append_setting_sources(settings)
       |> maybe_append_pair("--model", settings.model)
       |> maybe_append_pair("--agent", settings.agent)
       |> maybe_append_tools("--allowedTools", effective_allowed_tools(settings, tooling_runtime))
       |> maybe_append_tools("--disallowedTools", settings.disallowed_tools)}
    end
  end

  defp rendered_args(%Settings{transport: transport}, _opts), do: {:error, {:unsupported_transport, transport}}

  defp validate_command_conflicts(%Settings{transport: "acp_stdio"} = settings) do
    argv = configured_argv(settings)

    cond do
      contains_any_flag?(argv, @stdio_owned_conflict_flags) ->
        {:error, {:codebuddy_command_conflict, conflicting_flag(argv, @stdio_owned_conflict_flags)}}

      contains_flag?(argv, "--acp-transport") and option_value(argv, "--acp-transport") != "stdio" ->
        {:error, {:codebuddy_command_conflict, "--acp-transport"}}

      contains_any_flag?(argv, @single_source_flags) ->
        {:error, {:codebuddy_command_conflict, conflicting_flag(argv, @single_source_flags)}}

      contains_flag?(argv, "--setting-sources") and option_value(argv, "--setting-sources") != setting_sources(settings) ->
        {:error, {:codebuddy_command_conflict, "--setting-sources"}}

      true ->
        :ok
    end
  end

  defp validate_command_conflicts(%Settings{transport: "acp_http"} = settings) do
    argv = configured_argv(settings)

    cond do
      contains_any_flag?(argv, @http_owned_conflict_flags) ->
        {:error, {:codebuddy_command_conflict, conflicting_flag(argv, @http_owned_conflict_flags)}}

      contains_any_flag?(argv, @single_source_flags) ->
        {:error, {:codebuddy_command_conflict, conflicting_flag(argv, @single_source_flags)}}

      contains_flag?(argv, "--setting-sources") and option_value(argv, "--setting-sources") != setting_sources(settings) ->
        {:error, {:codebuddy_command_conflict, "--setting-sources"}}

      true ->
        :ok
    end
  end

  defp configured_argv(%Settings{} = settings) do
    case Settings.command_argv(settings) do
      argv when is_list(argv) -> argv
      nil -> split_command(settings.command)
    end
  end

  defp maybe_append_acp(parts, settings) do
    if contains_flag?(configured_argv(settings), "--acp"), do: parts, else: parts ++ ["--acp"]
  end

  defp maybe_append_acp_transport(parts, settings) do
    if contains_flag?(configured_argv(settings), "--acp-transport"), do: parts, else: parts ++ ["--acp-transport", "stdio"]
  end

  defp append_http_service_args(parts, settings) do
    parts
    |> Kernel.++(["--serve", "--host", Settings.http_bind_host(settings)])
    |> maybe_append_http_port(Settings.http_port(settings))
  end

  defp maybe_append_http_port(parts, :auto), do: parts
  defp maybe_append_http_port(parts, port) when is_integer(port), do: parts ++ ["--port", Integer.to_string(port)]

  defp append_runtime_mcp_args(parts, tooling_runtime), do: parts ++ SymphonyElixir.AgentProvider.CodeBuddyCode.Tooling.command_args(tooling_runtime)

  defp append_permission_args(parts, %Settings{permission_mode: "restricted"}, _tooling_runtime), do: parts ++ ["--permission-mode", "plan", "--tools", ""]

  defp append_permission_args(parts, %Settings{permission_mode: "planned_tools"}, tooling_runtime) do
    case SymphonyElixir.AgentProvider.CodeBuddyCode.Tooling.generated_allowed_tools(tooling_runtime) do
      [_tool | _] -> parts ++ ["--permission-mode", "plan"]
      _tools -> parts ++ ["--permission-mode", "plan", "--tools", ""]
    end
  end

  defp append_permission_args(parts, %Settings{permission_mode: "provider_default"}, _tooling_runtime), do: parts
  defp append_permission_args(parts, %Settings{permission_mode: "bypass_permissions"}, _tooling_runtime), do: parts ++ ["--permission-mode", "bypassPermissions"]

  defp maybe_append_setting_sources(parts, settings) do
    if contains_flag?(configured_argv(settings), "--setting-sources"), do: parts, else: parts ++ ["--setting-sources", setting_sources(settings)]
  end

  defp setting_sources(%Settings{credential_ref: credential_ref}) when is_binary(credential_ref) and credential_ref != "", do: ""
  defp setting_sources(%Settings{}), do: "user"

  defp maybe_append_pair(parts, _flag, nil), do: parts
  defp maybe_append_pair(parts, _flag, ""), do: parts
  defp maybe_append_pair(parts, flag, value) when is_binary(value), do: parts ++ [flag, value]

  defp maybe_append_tools(parts, _flag, []), do: parts
  defp maybe_append_tools(parts, flag, tools) when is_list(tools), do: parts ++ [flag, Enum.join(tools, ",")]

  defp effective_allowed_tools(%Settings{allowed_tools: allowed_tools, disallowed_tools: disallowed_tools, permission_mode: permission_mode}, tooling_runtime) do
    denied = MapSet.new(disallowed_tools)
    generated_tools = if permission_mode == "planned_tools", do: SymphonyElixir.AgentProvider.CodeBuddyCode.Tooling.generated_allowed_tools(tooling_runtime), else: []

    (allowed_tools ++ generated_tools)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(denied, &1))
  end

  defp contains_any_flag?(argv, flags), do: Enum.any?(flags, &contains_flag?(argv, &1))

  defp contains_flag?(argv, flag) when is_list(argv) and is_binary(flag) do
    Enum.any?(argv, fn arg -> arg == flag or String.starts_with?(arg, flag <> "=") end)
  end

  defp conflicting_flag(argv, flags), do: Enum.find(flags, &contains_flag?(argv, &1))

  defp option_value(argv, flag) do
    argv
    |> Enum.with_index()
    |> Enum.find_value(fn
      {^flag, index} -> Enum.at(argv, index + 1)
      {arg, _index} -> if String.starts_with?(arg, flag <> "="), do: String.replace_prefix(arg, flag <> "=", ""), else: nil
    end)
  end

  defp append_command_args(command, args) when is_binary(command), do: command <> " " <> shell_join(args)
  defp append_command_args(nil, args), do: shell_join(args)

  defp split_command(command) when is_binary(command), do: String.split(command, ~r/\s+/, trim: true)
  defp split_command(_command), do: []

  defp shell_join(argv) when is_list(argv), do: Enum.map_join(argv, " ", &shell_escape/1)
  defp shell_escape(value) when is_binary(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"

  defp command_metadata(%Settings{} = settings, args, opts) do
    tooling_runtime = Keyword.get(opts, :codebuddy_code_tooling_runtime)

    %{
      transport: settings.transport,
      rendered_argc: length(args),
      permission_mode: settings.permission_mode,
      mcp_dynamic_tools: match?(%{enabled?: true}, tooling_runtime),
      mcp_dynamic_tool_count: tooling_tool_count(tooling_runtime),
      acp_file_proxy: false,
      acp_terminal_proxy: false,
      setting_sources: setting_sources(settings),
      http_bind_host: http_bind_host_metadata(settings),
      http_port: http_port_metadata(settings)
    }
  end

  defp http_bind_host_metadata(%Settings{transport: "acp_http"} = settings), do: Settings.http_bind_host(settings)
  defp http_bind_host_metadata(%Settings{}), do: nil
  defp http_port_metadata(%Settings{transport: "acp_http"} = settings), do: Settings.http_port(settings)
  defp http_port_metadata(%Settings{}), do: nil

  defp tooling_tool_count(%{tool_names: tool_names}) when is_list(tool_names), do: length(tool_names)
  defp tooling_tool_count(_tooling_runtime), do: 0
end
