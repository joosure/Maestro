defmodule SymphonyElixir.AgentProvider.Codex.Tooling do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.Tooling.{
    McpConfig,
    RemoteBootstrap,
    RuntimeServer,
    ToolSpecs
  }

  alias SymphonyElixir.Agent.DynamicTool.Inventory.RenderOptions

  @spec server_relative_path() :: String.t()
  def server_relative_path, do: McpConfig.server_relative_path()

  @spec server_path(Path.t()) :: Path.t()
  def server_path(workspace) when is_binary(workspace), do: McpConfig.server_path(workspace)

  @spec wrapper_relative_path() :: String.t()
  def wrapper_relative_path, do: McpConfig.wrapper_relative_path()

  @spec wrapper_path(Path.t()) :: Path.t()
  def wrapper_path(workspace) when is_binary(workspace), do: McpConfig.wrapper_path(workspace)

  @spec mcp_tool_name(String.t()) :: String.t()
  def mcp_tool_name(tool) when is_binary(tool), do: McpConfig.tool_name(tool)

  @spec dynamic_tool_inventory_opts() :: keyword()
  def dynamic_tool_inventory_opts do
    [
      {RenderOptions.provider_callable_name_key(), &mcp_tool_name/1},
      {RenderOptions.provider_callable_label_key(), "Codex MCP tool"},
      {RenderOptions.provider_callable_note_key(),
       "Codex exposes Symphony Dynamic Tools through the runtime MCP bridge. The inventory lists the exact MCP-qualified callable name for each capability and the internal Symphony runtime tool separately."}
    ]
  end

  @spec write_runtime_mcp_server(Path.t(), keyword()) :: :ok | {:error, term()}
  def write_runtime_mcp_server(workspace, opts) when is_binary(workspace) and is_list(opts) do
    RuntimeServer.write(workspace, ToolSpecs.from_opts(opts), opts)
  end

  @spec mcp_config_args(keyword()) :: [String.t()]
  def mcp_config_args(opts) when is_list(opts) do
    opts
    |> ToolSpecs.from_opts()
    |> McpConfig.args()
  end

  @spec remote_setup_commands(Path.t(), keyword()) :: [String.t()]
  def remote_setup_commands(workspace, opts) when is_binary(workspace) and is_list(opts) do
    case ToolSpecs.from_opts(opts) do
      [_tool | _] = tool_specs -> ["(#{RemoteBootstrap.script(workspace, tool_specs, opts)})"]
      _tools -> []
    end
  end
end
