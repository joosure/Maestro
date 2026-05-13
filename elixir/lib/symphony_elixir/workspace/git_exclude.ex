defmodule SymphonyElixir.Workspace.GitExclude do
  @moduledoc false

  @spec ensure_entry(Path.t(), String.t()) :: :ok | {:error, term()}
  def ensure_entry(workspace, entry) when is_binary(workspace) and is_binary(entry) do
    with {:ok, exclude_path} <- git_exclude_path(workspace),
         :ok <- File.mkdir_p(Path.dirname(exclude_path)),
         {:ok, existing} <- read_existing(exclude_path),
         :ok <- write_entry(exclude_path, existing, entry) do
      :ok
    else
      :no_git_metadata -> :ok
      {:error, reason} -> {:error, {:git_exclude_failed, reason}}
    end
  end

  defp read_existing(exclude_path) do
    case File.read(exclude_path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, {:read_failed, exclude_path, reason}}
    end
  end

  defp write_entry(exclude_path, contents, entry) when is_binary(exclude_path) and is_binary(contents) and is_binary(entry) do
    if exclude_contains?(contents, entry) do
      :ok
    else
      prefix = if contents == "" or String.ends_with?(contents, "\n"), do: contents, else: contents <> "\n"

      case File.write(exclude_path, prefix <> entry <> "\n") do
        :ok -> :ok
        {:error, reason} -> {:error, {:write_failed, exclude_path, reason}}
      end
    end
  end

  defp exclude_contains?(contents, entry) when is_binary(contents) and is_binary(entry) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.member?(entry)
  end

  defp git_exclude_path(workspace) do
    git_path = Path.join(workspace, ".git")

    cond do
      File.dir?(git_path) ->
        {:ok, Path.join([git_path, "info", "exclude"])}

      File.regular?(git_path) ->
        with {:ok, contents} <- File.read(git_path),
             {:ok, git_dir} <- parse_git_dir(contents, workspace) do
          {:ok, Path.join([git_dir, "info", "exclude"])}
        else
          {:error, reason} -> {:error, {:git_file_read_failed, git_path, reason}}
          :error -> :no_git_metadata
        end

      true ->
        :no_git_metadata
    end
  end

  defp parse_git_dir(contents, workspace) when is_binary(contents) do
    case contents
         |> String.split("\n", trim: true)
         |> Enum.find(&String.starts_with?(&1, "gitdir:")) do
      nil ->
        :error

      line ->
        git_dir =
          line
          |> String.replace_prefix("gitdir:", "")
          |> String.trim()
          |> Path.expand(workspace)

        {:ok, git_dir}
    end
  end
end
