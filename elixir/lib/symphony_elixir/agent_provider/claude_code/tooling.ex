defmodule SymphonyElixir.AgentProvider.ClaudeCode.Tooling do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.ClaudeCode.Tooling.{
    McpConfig,
    RemoteBootstrap,
    ToolSpecs
  }

  alias SymphonyElixir.AgentProvider.PlannedToolMcpServer
  alias SymphonyElixir.Workspace.GitExclude
  alias SymphonyElixir.Workspace.Remote, as: WorkspaceRemote

  @git_exclude_entry ".symphony/"

  @spec prepare_workspace(Path.t(), keyword()) :: :ok | {:error, term()}
  def prepare_workspace(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    case Keyword.get(opts, :worker_host) do
      worker_host when is_binary(worker_host) ->
        prepare_remote_workspace(workspace, worker_host, opts)

      _ ->
        prepare_local_workspace(workspace, opts)
    end
  end

  @spec mcp_config_relative_path() :: String.t()
  def mcp_config_relative_path, do: McpConfig.relative_path()

  @spec mcp_tool_name(String.t()) :: String.t()
  def mcp_tool_name(tool) when is_binary(tool), do: McpConfig.tool_name(tool)

  @spec dynamic_tool_inventory_opts() :: keyword()
  def dynamic_tool_inventory_opts do
    [
      provider_callable_name: &mcp_tool_name/1,
      provider_callable_label: "Claude Code MCP tool",
      provider_callable_note:
        "Claude Code exposes Symphony Dynamic Tools through MCP. The inventory lists the exact MCP-qualified callable name for each capability and the internal Symphony runtime tool separately."
    ]
  end

  @spec write_runtime_mcp_config(Path.t(), keyword(), map()) :: :ok | {:error, term()}
  def write_runtime_mcp_config(workspace, opts, bridge_env)
      when is_binary(workspace) and is_list(opts) and is_map(bridge_env) do
    tool_specs = ToolSpecs.from_opts(opts)
    config_path = McpConfig.path(workspace)
    server_path = McpConfig.server_path(workspace)

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, McpConfig.source(tool_specs, bridge_env)),
         :ok <- maybe_write_server(server_path, tool_specs),
         :ok <- File.chmod(config_path, 0o600) do
      :ok
    else
      {:error, reason} -> {:error, {:claude_code_runtime_tooling_failed, reason}}
    end
  end

  defp prepare_local_workspace(workspace, opts) do
    tool_specs = ToolSpecs.from_opts(opts)
    config_path = McpConfig.path(workspace)
    server_path = McpConfig.server_path(workspace)

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, McpConfig.source(tool_specs)),
         :ok <- maybe_write_server(server_path, tool_specs),
         :ok <- GitExclude.ensure_entry(workspace, @git_exclude_entry) do
      :ok
    else
      {:error, reason} -> {:error, {:claude_code_tooling_failed, reason}}
    end
  end

  defp prepare_remote_workspace(workspace, worker_host, opts) do
    tool_specs = ToolSpecs.from_opts(opts)
    script = RemoteBootstrap.script(workspace, tool_specs)

    case remote_runner(worker_host, opts).(script) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {output, status}} ->
        {:error, {:claude_code_tooling_failed, {:remote_bootstrap_failed, worker_host, status, output}}}

      {:error, reason} ->
        {:error, {:claude_code_tooling_failed, reason}}
    end
  end

  defp maybe_write_server(server_path, [_tool_spec | _] = tool_specs) do
    with :ok <- File.write(server_path, PlannedToolMcpServer.source(tool_specs)),
         :ok <- File.chmod(server_path, 0o755) do
      :ok
    end
  end

  defp maybe_write_server(server_path, _tool_specs) do
    case File.rm(server_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp remote_runner(worker_host, opts) do
    case Keyword.get(opts, :remote_runner) do
      runner when is_function(runner, 1) ->
        runner

      _runner ->
        timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
        WorkspaceRemote.remote_command_runner(worker_host, timeout_ms)
    end
  end
end
