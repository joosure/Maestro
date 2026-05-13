defmodule SymphonyElixir.AgentProvider.Codex.Tooling.RuntimeServer do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.Tooling.{BridgeEnv, McpConfig, WrapperSource}
  alias SymphonyElixir.AgentProvider.PlannedToolMcpServer
  alias SymphonyElixir.Workspace.GitExclude

  @git_exclude_entry ".symphony/"

  @spec write(Path.t(), [map()], keyword()) :: :ok | {:error, term()}
  def write(workspace, tool_specs, opts) when is_binary(workspace) and is_list(tool_specs) and is_list(opts) do
    with {:ok, mcp_env} <- BridgeEnv.runtime(opts),
         :ok <- maybe_write_server(workspace, tool_specs, mcp_env),
         :ok <- maybe_ensure_git_exclude(workspace, tool_specs) do
      :ok
    else
      {:error, reason} -> {:error, {:codex_runtime_tooling_failed, reason}}
    end
  end

  defp maybe_write_server(workspace, [_tool | _] = tool_specs, mcp_env) do
    server_path = McpConfig.server_path(workspace)
    wrapper_path = McpConfig.wrapper_path(workspace)

    with :ok <- File.mkdir_p(Path.dirname(server_path)),
         :ok <- File.write(server_path, PlannedToolMcpServer.source(tool_specs)),
         :ok <- File.chmod(server_path, 0o755),
         :ok <- File.write(wrapper_path, WrapperSource.source(mcp_env)),
         :ok <- File.chmod(wrapper_path, 0o700) do
      :ok
    end
  end

  defp maybe_write_server(workspace, _tool_specs, _mcp_env) do
    with :ok <- rm_if_exists(McpConfig.server_path(workspace)),
         :ok <- rm_if_exists(McpConfig.wrapper_path(workspace)) do
      :ok
    end
  end

  defp rm_if_exists(path) when is_binary(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_ensure_git_exclude(workspace, [_tool | _]), do: GitExclude.ensure_entry(workspace, @git_exclude_entry)
  defp maybe_ensure_git_exclude(_workspace, _tool_specs), do: :ok
end
