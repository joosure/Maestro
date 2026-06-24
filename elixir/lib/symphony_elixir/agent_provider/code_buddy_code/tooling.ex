defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.Tooling do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context, as: DynamicToolContext
  alias SymphonyElixir.Agent.DynamicTool.Inventory.RenderOptions
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.Settings

  alias SymphonyElixir.AgentProvider.CodeBuddyCode.Tooling.{
    McpConfig,
    ToolSpecs
  }

  alias SymphonyElixir.AgentProvider.PlannedToolMcpServer
  alias SymphonyElixir.Workspace.GitExclude

  @git_exclude_entry ".symphony/"

  @spec prepare_workspace(Path.t(), Settings.t(), keyword()) :: :ok | {:error, term()}
  def prepare_workspace(workspace, %Settings{} = settings, _opts \\ []) when is_binary(workspace) do
    if Settings.mcp_enabled?(settings) do
      GitExclude.ensure_entry(workspace, @git_exclude_entry)
    else
      :ok
    end
  end

  @spec tool_context(Settings.t(), keyword()) :: DynamicToolContext.t()
  def tool_context(%Settings{} = settings, opts) when is_list(opts) do
    if Settings.mcp_enabled?(settings), do: ToolSpecs.tool_context(opts), else: DynamicToolContext.empty()
  end

  @spec mcp_tool_name(String.t()) :: String.t()
  def mcp_tool_name(tool) when is_binary(tool), do: McpConfig.tool_name(tool)

  @spec dynamic_tool_inventory_opts() :: keyword()
  def dynamic_tool_inventory_opts do
    [
      {RenderOptions.provider_callable_name_key(), &mcp_tool_name/1},
      {RenderOptions.provider_callable_label_key(), "CodeBuddy MCP tool"},
      {RenderOptions.provider_callable_note_key(),
       "CodeBuddy Code exposes Symphony Dynamic Tools through a session-scoped MCP server. The inventory lists the exact MCP-qualified callable name for each capability and the internal Symphony runtime tool separately."}
    ]
  end

  @spec write_runtime_mcp_config(Path.t(), Settings.t(), keyword(), map()) :: {:ok, map()} | {:error, term()}
  def write_runtime_mcp_config(workspace, %Settings{} = settings, opts, bridge_env)
      when is_binary(workspace) and is_list(opts) and is_map(bridge_env) do
    tool_specs = ToolSpecs.from_opts(opts)
    session_id = Keyword.get(opts, :session_id) || Ecto.UUID.generate()
    runtime = McpConfig.runtime(settings, session_id, tool_specs)

    if Settings.mcp_enabled?(settings) do
      write_runtime_files(workspace, runtime, tool_specs, bridge_env)
    else
      {:ok, runtime}
    end
  end

  @spec metadata(map() | nil) :: map()
  def metadata(runtime), do: McpConfig.metadata(runtime)

  @spec command_args(map() | nil) :: [String.t()]
  def command_args(%{enabled?: true} = runtime) do
    [
      "--mcp-config",
      runtime.mcp_config_relative_path,
      "--strict-mcp-config",
      "--settings",
      runtime.settings_relative_path
    ]
  end

  def command_args(_runtime), do: []

  @spec generated_allowed_tools(map() | nil) :: [String.t()]
  def generated_allowed_tools(%{enabled?: true, server_name: server_name, tool_names: tool_names})
      when is_binary(server_name) and is_list(tool_names) do
    Enum.map(tool_names, &McpConfig.tool_name(server_name, &1))
  end

  def generated_allowed_tools(_runtime), do: []

  defp write_runtime_files(workspace, runtime, tool_specs, bridge_env) do
    mcp_config_path = Path.join(workspace, runtime.mcp_config_relative_path)
    settings_path = Path.join(workspace, runtime.settings_relative_path)
    server_path = Path.join(workspace, runtime.server_relative_path)
    manifest_path = Path.join(workspace, runtime.manifest_relative_path)

    with :ok <- File.mkdir_p(Path.dirname(mcp_config_path)),
         :ok <- File.write(mcp_config_path, McpConfig.mcp_config_source(runtime, bridge_env)),
         :ok <- File.write(settings_path, McpConfig.settings_source(runtime)),
         :ok <- maybe_write_server(server_path, runtime, tool_specs),
         :ok <- File.mkdir_p(Path.dirname(manifest_path)),
         :ok <- File.write(manifest_path, McpConfig.manifest_source(runtime)),
         :ok <- File.chmod(mcp_config_path, 0o600),
         :ok <- File.chmod(settings_path, 0o600),
         :ok <- File.chmod(manifest_path, 0o600),
         :ok <- GitExclude.ensure_entry(workspace, @git_exclude_entry) do
      {:ok, runtime}
    else
      {:error, reason} -> {:error, {:codebuddy_code_runtime_tooling_failed, reason}}
    end
  end

  defp maybe_write_server(server_path, %{enabled?: true}, [_tool_spec | _] = tool_specs) do
    with :ok <- File.write(server_path, PlannedToolMcpServer.source(tool_specs)),
         :ok <- File.chmod(server_path, 0o755) do
      :ok
    end
  end

  defp maybe_write_server(server_path, _runtime, _tool_specs) do
    case File.rm(server_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
