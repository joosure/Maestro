defmodule SymphonyElixir.AgentProvider.Codex.Tooling.McpConfig do
  @moduledoc false

  @bundle_root [".symphony", "codex"]
  @server_path @bundle_root ++ ["planned_tools_mcp.js"]
  @wrapper_path @bundle_root ++ ["planned_tools_mcp.sh"]
  @server_name "symphony-planned-tools"

  @spec bundle_relative_path() :: String.t()
  def bundle_relative_path, do: Path.join(@bundle_root)

  @spec server_name() :: String.t()
  def server_name, do: @server_name

  @spec tool_name(String.t()) :: String.t()
  def tool_name(tool) when is_binary(tool), do: "mcp__#{@server_name}__#{tool}"

  @spec server_relative_path() :: String.t()
  def server_relative_path, do: Path.join(@server_path)

  @spec server_path(Path.t()) :: Path.t()
  def server_path(workspace) when is_binary(workspace), do: Path.join([workspace | @server_path])

  @spec wrapper_relative_path() :: String.t()
  def wrapper_relative_path, do: Path.join(@wrapper_path)

  @spec wrapper_path(Path.t()) :: Path.t()
  def wrapper_path(workspace) when is_binary(workspace), do: Path.join([workspace | @wrapper_path])

  @spec args([map()]) :: [String.t()]
  def args([_tool_spec | _]) do
    [
      "--config",
      "mcp_servers={}",
      "--config",
      "mcp_servers.#{@server_name}.command=\"sh\"",
      "--config",
      "mcp_servers.#{@server_name}.args=[#{toml_string(wrapper_relative_path())}]"
    ]
  end

  def args(_tool_specs), do: []

  defp toml_string(value) when is_binary(value), do: Jason.encode!(value)
end
