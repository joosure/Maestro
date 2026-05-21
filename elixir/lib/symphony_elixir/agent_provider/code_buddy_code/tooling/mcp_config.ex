defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.Tooling.McpConfig do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.CodeBuddyCode.Settings

  @bundle_root [".symphony", "codebuddy"]
  @sessions_dir @bundle_root ++ ["sessions"]
  @mcp_filename "mcp.json"
  @settings_filename "settings.json"
  @server_filename "planned_tools_mcp.js"
  @manifest_path @bundle_root ++ ["manifest.json"]

  @type runtime :: %{
          required(:enabled?) => boolean(),
          required(:session_id) => String.t(),
          required(:server_name) => String.t(),
          required(:tool_names) => [String.t()],
          required(:mcp_config_relative_path) => String.t(),
          required(:settings_relative_path) => String.t(),
          required(:server_relative_path) => String.t(),
          required(:manifest_relative_path) => String.t()
        }

  @spec tool_name(String.t()) :: String.t()
  def tool_name(tool) when is_binary(tool), do: "mcp__#{Settings.default_mcp_server_name()}__#{tool}"

  @spec tool_name(String.t(), String.t()) :: String.t()
  def tool_name(server_name, tool) when is_binary(server_name) and is_binary(tool), do: "mcp__#{server_name}__#{tool}"

  @spec session_root_relative_path(String.t()) :: String.t()
  def session_root_relative_path(session_id), do: Path.join(@sessions_dir ++ [safe_segment(session_id)])

  @spec runtime(Settings.t(), String.t(), [map()]) :: runtime()
  def runtime(%Settings{} = settings, session_id, tool_specs) when is_binary(session_id) and is_list(tool_specs) do
    safe_session_id = safe_segment(session_id)
    server_name = Settings.mcp_server_name(settings)
    session_path = @sessions_dir ++ [safe_session_id]
    tool_names = tool_names(tool_specs)

    %{
      enabled?: Settings.mcp_enabled?(settings) and tool_names != [],
      session_id: safe_session_id,
      server_name: server_name,
      tool_names: tool_names,
      mcp_config_relative_path: Path.join(session_path ++ [@mcp_filename]),
      settings_relative_path: Path.join(session_path ++ [@settings_filename]),
      server_relative_path: Path.join(session_path ++ [@server_filename]),
      manifest_relative_path: Path.join(@manifest_path)
    }
  end

  @spec mcp_config_source(runtime(), map()) :: String.t()
  def mcp_config_source(%{enabled?: true} = runtime, bridge_env) when is_map(bridge_env) do
    server =
      %{
        "type" => "stdio",
        "command" => "node",
        "args" => [runtime.server_relative_path]
      }
      |> maybe_put_env(bridge_env)

    %{
      "mcpServers" => %{
        runtime.server_name => server
      },
      "disabledMcpServers" => []
    }
    |> Jason.encode!(pretty: true)
  end

  def mcp_config_source(%{} = _runtime, _bridge_env) do
    Jason.encode!(%{"mcpServers" => %{}, "disabledMcpServers" => []}, pretty: true)
  end

  @spec settings_source(runtime()) :: String.t()
  def settings_source(%{enabled?: true} = runtime) do
    %{
      "enabledMcpjsonServers" => [runtime.server_name],
      "permissions" => %{
        "allow" => ["mcp__#{runtime.server_name}"]
      }
    }
    |> Jason.encode!(pretty: true)
  end

  def settings_source(%{} = _runtime) do
    Jason.encode!(%{"enabledMcpjsonServers" => [], "permissions" => %{"allow" => []}}, pretty: true)
  end

  @spec manifest_source(runtime()) :: String.t()
  def manifest_source(%{} = runtime) do
    files =
      [
        runtime.mcp_config_relative_path,
        runtime.settings_relative_path,
        if(runtime.enabled?, do: runtime.server_relative_path)
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "version" => 1,
      "provider" => "codebuddy_code",
      "sessions" => [
        %{
          "session_id" => runtime.session_id,
          "server_name" => runtime.server_name,
          "tool_names" => runtime.tool_names,
          "files" => files
        }
      ]
    }
    |> Jason.encode!(pretty: true)
  end

  @spec metadata(runtime() | nil) :: map()
  def metadata(%{} = runtime) do
    %{
      enabled: runtime.enabled?,
      session_id: runtime.session_id,
      server_name: runtime.server_name,
      tool_count: length(runtime.tool_names),
      mcp_config_relative_path: runtime.mcp_config_relative_path,
      settings_relative_path: runtime.settings_relative_path,
      server_relative_path: runtime.server_relative_path
    }
  end

  def metadata(_runtime), do: %{}

  defp tool_names(tool_specs) do
    tool_specs
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) and name != "" -> [name]
      %{name: name} when is_binary(name) and name != "" -> [name]
      _tool_spec -> []
    end)
    |> Enum.uniq()
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

  defp safe_segment(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "_")
    |> String.trim(".")
    |> case do
      "" -> Ecto.UUID.generate()
      segment -> segment
    end
  end
end
