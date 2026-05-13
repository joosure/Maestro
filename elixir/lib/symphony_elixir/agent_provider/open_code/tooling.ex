defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.OpenCode.Tooling.{Manifest, ToolEntries, ToolFiles, ToolSpecs}
  alias SymphonyElixir.Workspace.GitExclude

  @git_exclude_entry ".opencode/"

  @spec prepare_workspace(Path.t(), keyword()) :: :ok | {:error, term()}
  def prepare_workspace(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    case Keyword.get(opts, :worker_host) do
      worker_host when is_binary(worker_host) ->
        {:error, {:remote_unsupported, worker_host}}

      _ ->
        prepare_local_workspace(workspace, opts)
    end
  end

  defp prepare_local_workspace(workspace, opts) do
    tool_specs = ToolSpecs.from_opts(opts)
    tool_entries = ToolEntries.from_specs(tool_specs)
    current_files = Enum.map(tool_entries, fn {filename, _tool_spec} -> filename end)

    case ToolFiles.remove_stale(workspace, Manifest.files(workspace), current_files) do
      :ok ->
        case tool_entries do
          [_entry | _] -> ensure_tool_files(workspace, tool_entries)
          _entries -> remove_manifest(workspace)
        end

      {:error, reason} ->
        {:error, {:opencode_tooling_failed, reason}}
    end
  end

  defp ensure_tool_files(workspace, tool_entries) do
    with :ok <- ToolFiles.write_all(workspace, tool_entries),
         :ok <- Manifest.write(workspace, tool_entries),
         :ok <- GitExclude.ensure_entry(workspace, @git_exclude_entry) do
      :ok
    else
      {:error, reason} -> {:error, {:opencode_tooling_failed, reason}}
    end
  end

  defp remove_manifest(workspace) do
    case Manifest.remove(workspace) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, {:opencode_tooling_failed, reason}}
    end
  end
end
