defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling.Manifest do
  @moduledoc false

  @tool_root [".opencode", "tools"]
  @manifest_path @tool_root ++ [".symphony-planned-tools.json"]

  @spec path(Path.t()) :: Path.t()
  def path(workspace) when is_binary(workspace), do: Path.join([workspace | @manifest_path])

  @spec write(Path.t(), [{String.t(), map()}]) :: :ok | {:error, term()}
  def write(workspace, tool_entries) when is_binary(workspace) and is_list(tool_entries) do
    files = Enum.map(tool_entries, fn {filename, _tool_spec} -> filename end)
    File.write(path(workspace), Jason.encode!(%{"files" => files}, pretty: true))
  end

  @spec remove(Path.t()) :: :ok | {:error, term()}
  def remove(workspace) when is_binary(workspace), do: File.rm(path(workspace))

  @spec files(Path.t()) :: [String.t()]
  def files(workspace) when is_binary(workspace) do
    workspace
    |> path()
    |> File.read()
    |> case do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"files" => files}} when is_list(files) -> Enum.filter(files, &safe_file?/1)
          _payload -> []
        end

      {:error, _reason} ->
        []
    end
  end

  defp safe_file?(filename) when is_binary(filename) do
    filename == Path.basename(filename) and filename not in ["", ".", ".."]
  end

  defp safe_file?(_filename), do: false
end
