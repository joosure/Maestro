defmodule SymphonyElixir.AgentProvider.ClaudeCode.Tooling.McpConfig do
  @moduledoc false

  @bundle_root [".symphony", "claude"]
  @config_path @bundle_root ++ ["mcp.json"]
  @server_path @bundle_root ++ ["planned_tools_mcp.js"]
  @server_name "symphony-planned-tools"

  @spec bundle_relative_path() :: String.t()
  def bundle_relative_path, do: Path.join(@bundle_root)

  @spec server_name() :: String.t()
  def server_name, do: @server_name

  @spec tool_name(String.t()) :: String.t()
  def tool_name(tool) when is_binary(tool), do: "mcp__#{@server_name}__#{tool}"

  @spec relative_path() :: String.t()
  def relative_path, do: Path.join(@config_path)

  @spec path(Path.t()) :: Path.t()
  def path(workspace) when is_binary(workspace), do: Path.join([workspace | @config_path])

  @spec server_relative_path() :: String.t()
  def server_relative_path, do: Path.join(@server_path)

  @spec server_path(Path.t()) :: Path.t()
  def server_path(workspace) when is_binary(workspace), do: Path.join([workspace | @server_path])

  @spec source([map()], map()) :: String.t()
  def source(tool_specs, env \\ %{})

  def source([_tool_spec | _], env) when is_map(env) do
    server =
      %{
        "command" => "node",
        "args" => [server_relative_path()]
      }
      |> maybe_put_env(env)

    %{
      "mcpServers" => %{
        @server_name => server
      }
    }
    |> Jason.encode!(pretty: true)
  end

  def source(_tool_specs, _env) do
    Jason.encode!(%{"mcpServers" => %{}}, pretty: true)
  end

  defp maybe_put_env(server, env) do
    env =
      env
      |> Enum.flat_map(fn
        {key, value} when is_binary(key) and is_binary(value) and value != "" -> [{key, value}]
        _entry -> []
      end)
      |> Map.new()

    case env do
      empty when empty == %{} -> server
      env -> Map.put(server, "env", env)
    end
  end
end
