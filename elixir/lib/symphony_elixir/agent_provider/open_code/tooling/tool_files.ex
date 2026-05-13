defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling.ToolFiles do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin

  @tool_root [".opencode", "tools"]

  @spec write_all(Path.t(), [{String.t(), map()}]) :: :ok | {:error, term()}
  def write_all(workspace, tool_entries) when is_binary(workspace) and is_list(tool_entries) do
    tool_dir = root_path(workspace)

    with :ok <- File.mkdir_p(tool_dir) do
      Enum.reduce_while(tool_entries, :ok, fn {filename, tool_spec}, :ok ->
        case File.write(Path.join(tool_dir, filename), PlannedToolPlugin.render(tool_spec)) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @spec remove_stale(Path.t(), [String.t()], [String.t()]) :: :ok | {:error, term()}
  def remove_stale(workspace, manifest_files, current_files)
      when is_binary(workspace) and is_list(manifest_files) and is_list(current_files) do
    current_files = MapSet.new(current_files)
    tool_dir = root_path(workspace)

    manifest_files
    |> Enum.reject(&MapSet.member?(current_files, &1))
    |> Enum.reduce_while(:ok, fn filename, :ok ->
      case File.rm(Path.join(tool_dir, filename)) do
        :ok -> {:cont, :ok}
        {:error, :enoent} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp root_path(workspace), do: Path.join([workspace | @tool_root])
end
