defmodule SymphonyElixir.Workspace.AutomationPack do
  @moduledoc false

  alias SymphonyElixir.Workspace.Paths

  @bundle_dirname "workspace_automation"
  @cache_rootname "symphony-elixir-workspace-automation-pack"
  @runtime_env_var "SYMPHONY_WORKSPACE_AUTOMATION_DIR"
  @cli_env_var "SYMPHONY_CLI"

  @type source_kind :: :bundled | :override

  @spec runtime_env_var() :: String.t()
  def runtime_env_var, do: @runtime_env_var

  @spec cli_env_var() :: String.t()
  def cli_env_var, do: @cli_env_var

  @spec destination_dir(Path.t(), String.t()) :: Path.t()
  def destination_dir(workspace, destination_dirname)
      when is_binary(workspace) and is_binary(destination_dirname) do
    Path.join(workspace, destination_dirname)
  end

  @spec runtime_env(Path.t(), String.t()) :: [{String.t(), String.t()}]
  def runtime_env(workspace, destination_dirname)
      when is_binary(workspace) and is_binary(destination_dirname) do
    workspace_env = [{@runtime_env_var, destination_dir(workspace, destination_dirname)}]

    case current_cli_path() do
      {:ok, cli_path} -> [{@cli_env_var, cli_path} | workspace_env]
      :error -> workspace_env
    end
  end

  @spec remote_shell_assign(Path.t(), String.t()) :: String.t()
  def remote_shell_assign(workspace, destination_dirname)
      when is_binary(workspace) and is_binary(destination_dirname) do
    [
      Paths.remote_shell_assign(@runtime_env_var, destination_dir(workspace, destination_dirname)),
      "export #{@runtime_env_var}"
    ]
    |> Enum.join("\n")
  end

  @spec source_dir(nil | String.t()) :: {:ok, source_kind(), Path.t()} | {:error, term()}
  def source_dir(override_dir \\ nil)

  def source_dir(override_dir) when is_binary(override_dir) and override_dir != "" do
    {:ok, :override, override_dir}
  end

  def source_dir(_override_dir) do
    with {:ok, bundled_dir} <- bundled_source_dir() do
      {:ok, :bundled, bundled_dir}
    end
  end

  @spec bundled_source_dir() :: {:ok, Path.t()} | {:error, term()}
  def bundled_source_dir do
    case application_priv_source_dir() do
      {:ok, bundled_dir} ->
        {:ok, bundled_dir}

      {:error, _reason} ->
        extract_bundled_source_dir()
    end
  end

  defp application_priv_source_dir do
    case Application.app_dir(:symphony_elixir, Path.join("priv", @bundle_dirname)) do
      path when is_binary(path) ->
        cond do
          File.dir?(path) ->
            {:ok, path}

          File.exists?(path) ->
            {:error, {:bundled_automation_pack_not_directory, path}}

          true ->
            {:error, {:bundled_automation_pack_missing, path}}
        end
    end
  rescue
    ArgumentError ->
      {:error, :bundled_automation_pack_missing}
  end

  defp extract_bundled_source_dir do
    with {:ok, script_path} <- escript_path(),
         {:ok, cache_root} <- extraction_cache_root(script_path),
         {:ok, bundled_dir} <- ensure_extracted_bundle(script_path, cache_root) do
      {:ok, bundled_dir}
    else
      {:error, reason} ->
        {:error, {:workspace_bootstrap_automation_unavailable, reason}}
    end
  end

  defp escript_path do
    case :escript.script_name() do
      script_name when is_list(script_name) ->
        script_path = script_name |> List.to_string() |> Path.expand()

        cond do
          script_path in ["", Path.expand("-e")] ->
            {:error, :escript_script_name_unavailable}

          File.regular?(script_path) ->
            {:ok, script_path}

          true ->
            {:error, {:escript_script_not_found, script_path}}
        end
    end
  end

  defp extraction_cache_root(script_path) do
    case File.stat(script_path) do
      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        cache_key = :erlang.phash2({script_path, size, mtime}) |> Integer.to_string(36)
        {:ok, Path.join([System.tmp_dir!(), @cache_rootname, cache_key])}

      {:error, reason} ->
        {:error, {:escript_stat_failed, script_path, reason}}
    end
  end

  defp ensure_extracted_bundle(script_path, cache_root) do
    case find_extracted_bundle(cache_root) do
      {:ok, bundled_dir} ->
        {:ok, bundled_dir}

      {:error, _reason} ->
        File.rm_rf!(cache_root)
        File.mkdir_p!(cache_root)

        with {:ok, archive_bin} <- escript_archive(script_path),
             :ok <- unzip_archive(archive_bin, cache_root),
             {:ok, bundled_dir} <- find_extracted_bundle(cache_root) do
          {:ok, bundled_dir}
        end
    end
  end

  defp find_extracted_bundle(cache_root) do
    [cache_root, "**", "priv", @bundle_dirname]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.find(&File.dir?/1)
    |> case do
      nil -> {:error, {:bundled_automation_pack_missing_after_extract, cache_root}}
      bundled_dir -> {:ok, bundled_dir}
    end
  end

  defp escript_archive(script_path) do
    case :escript.extract(String.to_charlist(script_path), []) do
      {:ok, sections} ->
        case Keyword.fetch(sections, :archive) do
          {:ok, archive_bin} when is_binary(archive_bin) ->
            {:ok, archive_bin}

          {:ok, _section} ->
            {:error, :escript_archive_invalid}

          :error ->
            {:error, :escript_archive_missing}
        end

      {:error, reason} ->
        {:error, {:escript_extract_failed, reason}}
    end
  end

  defp unzip_archive(archive_bin, cache_root) when is_binary(archive_bin) and is_binary(cache_root) do
    case :zip.extract(archive_bin, [{:cwd, String.to_charlist(cache_root)}]) do
      {:ok, _paths} ->
        :ok

      {:error, reason} ->
        {:error, {:archive_extract_failed, reason}}
    end
  end

  defp current_cli_path do
    [
      System.get_env(@cli_env_var),
      escript_script_path(),
      System.find_executable("symphony")
    ]
    |> Enum.find_value(fn
      path when is_binary(path) and path != "" ->
        expanded = Path.expand(path)

        if File.regular?(expanded) do
          {:ok, expanded}
        else
          false
        end

      _path ->
        false
    end)
    |> case do
      {:ok, path} -> {:ok, path}
      nil -> :error
    end
  end

  defp escript_script_path do
    case :escript.script_name() do
      script_name when is_list(script_name) ->
        script_name
        |> List.to_string()
        |> case do
          script_path when script_path in ["", "-e"] -> nil
          script_path -> script_path
        end
    end
  rescue
    _error -> nil
  end
end
