defmodule SymphonyElixir.Workspace.Paths do
  @moduledoc false

  alias SymphonyElixir.PathSafety

  @remote_workspace_marker "__SYMPHONY_WORKSPACE__"
  @remote_workspace_error_marker "__SYMPHONY_WORKSPACE_ERROR__"
  @remote_workspace_missing_marker "__SYMPHONY_WORKSPACE_MISSING__"
  @remote_workspace_file_marker "__SYMPHONY_WORKSPACE_FILE__"

  @type worker_host :: String.t() | nil
  @type remote_runner :: (String.t() -> {:ok, {term(), integer()}} | {:error, term()})

  @spec safe_identifier(term()) :: String.t()
  def safe_identifier(identifier) do
    String.replace(identifier || "issue", ~r/[^a-zA-Z0-9._-]/, "_")
  end

  @spec workspace_path_for_issue(String.t(), Path.t(), worker_host()) ::
          {:ok, Path.t()} | {:error, term()}
  def workspace_path_for_issue(safe_id, workspace_root, nil)
      when is_binary(safe_id) and is_binary(workspace_root) do
    workspace_root
    |> Path.join(safe_id)
    |> PathSafety.canonicalize()
  end

  def workspace_path_for_issue(safe_id, workspace_root, worker_host)
      when is_binary(safe_id) and is_binary(workspace_root) and is_binary(worker_host) do
    {:ok, Path.join(workspace_root, safe_id)}
  end

  @spec workspace_path_hint(String.t(), Path.t(), worker_host()) :: Path.t()
  def workspace_path_hint(safe_id, workspace_root, nil)
      when is_binary(safe_id) and is_binary(workspace_root) do
    workspace_root
    |> Path.expand()
    |> Path.join(safe_id)
  end

  def workspace_path_hint(safe_id, workspace_root, worker_host)
      when is_binary(safe_id) and is_binary(workspace_root) and is_binary(worker_host) do
    Path.join(workspace_root, safe_id)
  end

  @spec validate_local_workspace_path(Path.t(), Path.t()) :: :ok | {:error, term()}
  def validate_local_workspace_path(workspace, workspace_root)
      when is_binary(workspace) and is_binary(workspace_root) do
    expanded_workspace = Path.expand(workspace)
    expanded_root = Path.expand(workspace_root)
    expanded_root_prefix = expanded_root <> "/"

    with {:ok, canonical_workspace} <- PathSafety.canonicalize(expanded_workspace),
         {:ok, canonical_root} <- PathSafety.canonicalize(expanded_root) do
      canonical_root_prefix = canonical_root <> "/"

      cond do
        canonical_workspace == canonical_root ->
          {:error, {:workspace_equals_root, canonical_workspace, canonical_root}}

        String.starts_with?(canonical_workspace <> "/", canonical_root_prefix) ->
          :ok

        String.starts_with?(expanded_workspace <> "/", expanded_root_prefix) ->
          {:error, {:workspace_symlink_escape, expanded_workspace, canonical_root}}

        true ->
          {:error, {:workspace_outside_root, canonical_workspace, canonical_root}}
      end
    else
      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:workspace_path_unreadable, path, reason}}
    end
  end

  @spec validate_remote_workspace_path(Path.t(), String.t()) :: :ok | {:error, term()}
  def validate_remote_workspace_path(workspace, worker_host)
      when is_binary(workspace) and is_binary(worker_host) do
    cond do
      String.trim(workspace) == "" ->
        {:error, {:workspace_path_unreadable, workspace, :empty}}

      String.contains?(workspace, ["\n", "\r", <<0>>]) ->
        {:error, {:workspace_path_unreadable, workspace, :invalid_characters}}

      true ->
        :ok
    end
  end

  @spec ensure_remote_workspace(Path.t(), Path.t(), String.t(), remote_runner()) ::
          {:ok, Path.t(), boolean()} | {:error, term()}
  def ensure_remote_workspace(workspace, workspace_root, worker_host, remote_runner)
      when is_binary(workspace) and is_binary(workspace_root) and is_binary(worker_host) and
             is_function(remote_runner, 1) do
    script =
      [
        "set -eu",
        remote_shell_assign("workspace_root", workspace_root),
        remote_shell_assign("workspace", workspace),
        "mkdir -p \"$workspace_root\"",
        "if [ -d \"$workspace\" ]; then",
        "  created=0",
        "elif [ -e \"$workspace\" ] || [ -L \"$workspace\" ]; then",
        "  rm -rf \"$workspace\"",
        "  mkdir -p \"$workspace\"",
        "  created=1",
        "else",
        "  mkdir -p \"$workspace\"",
        "  created=1",
        "fi",
        "canonical_root=$(cd \"$workspace_root\" && pwd -P)",
        "canonical_workspace=$(cd \"$workspace\" && pwd -P)",
        remote_workspace_boundary_validation_lines("canonical_root", "canonical_workspace"),
        "printf '%s\\t%s\\t%s\\t%s\\n' '#{@remote_workspace_marker}' \"$created\" \"$canonical_root\" \"$canonical_workspace\""
      ]
      |> List.flatten()
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    case remote_runner.(script) do
      {:ok, {output, status}} ->
        case parse_remote_workspace_output(output) do
          {:ok, %{workspace: canonical_workspace, created?: created?}} when status == 0 ->
            {:ok, canonical_workspace, created?}

          {:error, reason} ->
            {:error, reason}

          _other ->
            {:error, {:workspace_prepare_failed, worker_host, status, output}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec validate_remote_workspace_boundary(Path.t(), String.t(), Path.t(), remote_runner()) ::
          {:ok, Path.t()} | {:error, term()}
  def validate_remote_workspace_boundary(workspace, worker_host, workspace_root, remote_runner)
      when is_binary(workspace) and is_binary(worker_host) and is_binary(workspace_root) and
             is_function(remote_runner, 1) do
    case resolve_remote_workspace_for_cleanup(
           workspace,
           worker_host,
           workspace_root,
           remote_runner,
           require_directory: true
         ) do
      {:ok, :missing} ->
        {:error, {:workspace_path_unreadable, workspace, :missing}}

      {:ok, %{workspace: _workspace, directory?: false}} ->
        {:error, {:workspace_path_unreadable, workspace, :not_directory}}

      {:ok, %{workspace: canonical_workspace, directory?: true}} ->
        {:ok, canonical_workspace}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec resolve_remote_workspace_for_cleanup(
          Path.t(),
          String.t(),
          Path.t(),
          remote_runner(),
          keyword()
        ) :: {:ok, :missing | %{workspace: Path.t(), directory?: boolean()}} | {:error, term()}
  def resolve_remote_workspace_for_cleanup(
        workspace,
        worker_host,
        workspace_root,
        remote_runner,
        opts \\ []
      )
      when is_binary(workspace) and is_binary(worker_host) and is_binary(workspace_root) and
             is_function(remote_runner, 1) and is_list(opts) do
    require_directory = Keyword.get(opts, :require_directory, false)

    with :ok <- validate_remote_workspace_path(workspace, worker_host) do
      script =
        [
          "set -eu",
          remote_shell_assign("workspace_root", workspace_root),
          remote_shell_assign("workspace", workspace),
          "if [ ! -e \"$workspace\" ] && [ ! -L \"$workspace\" ]; then",
          "  printf '%s\\t%s\\n' '#{@remote_workspace_missing_marker}' \"$workspace\"",
          "  exit 0",
          "fi",
          "if [ ! -d \"$workspace\" ]; then",
          "  printf '%s\\t%s\\n' '#{@remote_workspace_file_marker}' \"$workspace\"",
          "  exit 0",
          "fi",
          "canonical_root=$(cd \"$workspace_root\" && pwd -P 2>/dev/null || printf '')",
          "if [ \"$canonical_root\" = '' ]; then",
          "  printf '%s\\t%s\\t%s\\t%s\\n' '#{@remote_workspace_error_marker}' 'workspace_root_unreadable' \"$workspace_root\" \"$workspace\"",
          "  exit 74",
          "fi",
          "canonical_workspace=$(cd \"$workspace\" && pwd -P 2>/dev/null || printf '')",
          "if [ \"$canonical_workspace\" = '' ]; then",
          "  printf '%s\\t%s\\t%s\\t%s\\n' '#{@remote_workspace_error_marker}' 'workspace_unreadable' \"$canonical_root\" \"$workspace\"",
          "  exit 75",
          "fi",
          remote_workspace_boundary_validation_lines("canonical_root", "canonical_workspace"),
          "printf '%s\\t%s\\t%s\\t%s\\n' '#{@remote_workspace_marker}' '0' \"$canonical_root\" \"$canonical_workspace\""
        ]
        |> List.flatten()
        |> Enum.join("\n")

      case remote_runner.(script) do
        {:ok, {output, status}} ->
          case parse_remote_workspace_output(output) do
            {:ok, %{workspace: canonical_workspace}} when status == 0 ->
              {:ok, %{workspace: canonical_workspace, directory?: true}}

            {:missing, _workspace} when status == 0 ->
              {:ok, :missing}

            {:file, resolved_workspace} when status == 0 and not require_directory ->
              {:ok, %{workspace: resolved_workspace, directory?: false}}

            {:file, _resolved_workspace} when status == 0 ->
              {:error, {:workspace_path_unreadable, workspace, :not_directory}}

            {:error, reason} ->
              {:error, reason}

            _other ->
              {:error, {:workspace_prepare_failed, worker_host, status, output}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec remote_shell_assign(String.t(), String.t()) :: String.t()
  def remote_shell_assign(variable_name, raw_path)
      when is_binary(variable_name) and is_binary(raw_path) do
    [
      "#{variable_name}=#{shell_escape(raw_path)}",
      "case \"$#{variable_name}\" in",
      "  '~') #{variable_name}=\"$HOME\" ;;",
      "  '~/'*) " <> variable_name <> "=\"$HOME/${" <> variable_name <> "#\\~/}\" ;;",
      "esac"
    ]
    |> Enum.join("\n")
  end

  @spec shell_escape(String.t()) :: String.t()
  def shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp parse_remote_workspace_output(output) do
    lines = String.split(IO.iodata_to_binary(output), "\n", trim: true)

    payload =
      Enum.find_value(lines, fn line ->
        case String.split(line, "\t", parts: 4) do
          [@remote_workspace_marker, created, root, path]
          when created in ["0", "1"] and root != "" and path != "" ->
            {:ok, %{created?: created == "1", root: root, workspace: path}}

          [@remote_workspace_marker, created, path] when created in ["0", "1"] and path != "" ->
            {:ok, %{created?: created == "1", root: nil, workspace: path}}

          [@remote_workspace_error_marker, code, root, path]
          when code != "" and root != "" and path != "" ->
            {:error, remote_workspace_error(code, path, root)}

          [@remote_workspace_missing_marker, path] when path != "" ->
            {:missing, path}

          [@remote_workspace_file_marker, path] when path != "" ->
            {:file, path}

          _other ->
            nil
        end
      end)

    case payload do
      {:ok, %{workspace: workspace} = parsed} when is_binary(workspace) ->
        {:ok, parsed}

      {:error, _reason} = error ->
        error

      {:missing, workspace} when is_binary(workspace) ->
        {:missing, workspace}

      {:file, workspace} when is_binary(workspace) ->
        {:file, workspace}

      _other ->
        :unknown
    end
  end

  defp remote_workspace_error("workspace_equals_root", workspace, root),
    do: {:workspace_equals_root, workspace, root}

  defp remote_workspace_error("workspace_outside_root", workspace, root),
    do: {:workspace_outside_root, workspace, root}

  defp remote_workspace_error("workspace_root_unreadable", workspace, root),
    do: {:workspace_path_unreadable, workspace, {:root_unreadable, root}}

  defp remote_workspace_error("workspace_unreadable", workspace, root),
    do: {:workspace_path_unreadable, workspace, {:remote_unreadable, root}}

  defp remote_workspace_error(code, workspace, root),
    do: {:workspace_path_unreadable, workspace, {:remote_validation_failed, code, root}}

  defp remote_workspace_boundary_validation_lines(root_variable, workspace_variable)
       when is_binary(root_variable) and is_binary(workspace_variable) do
    [
      "if [ \"$#{workspace_variable}\" = \"$#{root_variable}\" ]; then",
      "  printf '%s\\t%s\\t%s\\t%s\\n' '#{@remote_workspace_error_marker}' 'workspace_equals_root' \"$#{root_variable}\" \"$#{workspace_variable}\"",
      "  exit 72",
      "fi",
      "workspace_within_root=0",
      "if [ \"$#{root_variable}\" = '/' ]; then",
      "  workspace_within_root=1",
      "else",
      "  case \"$#{workspace_variable}\" in",
      "    \"$#{root_variable}\"/*) workspace_within_root=1 ;;",
      "  esac",
      "fi",
      "if [ \"$workspace_within_root\" != '1' ]; then",
      "  printf '%s\\t%s\\t%s\\t%s\\n' '#{@remote_workspace_error_marker}' 'workspace_outside_root' \"$#{root_variable}\" \"$#{workspace_variable}\"",
      "  exit 73",
      "fi"
    ]
  end
end
