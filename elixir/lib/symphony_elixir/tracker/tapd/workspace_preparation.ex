defmodule SymphonyElixir.Tracker.Tapd.WorkspacePreparation do
  @moduledoc false

  alias SymphonyElixir.Workspace.GitExclude
  alias SymphonyElixir.Workspace.Paths
  alias SymphonyElixir.Workspace.Remote, as: WorkspaceRemote

  @workpad_filename ".symphony-tapd-workpad.md"

  @type worker_host :: String.t() | nil
  @type remote_runner :: (String.t() -> {:ok, {term(), integer()}} | {:error, term()})

  @spec ensure_workpad_ignore(Path.t(), worker_host(), keyword()) :: :ok | {:error, term()}
  def ensure_workpad_ignore(workspace, worker_host, opts \\ [])

  def ensure_workpad_ignore(workspace, nil, _opts) when is_binary(workspace) do
    workspace
    |> local_ignore_candidates()
    |> Enum.reduce_while(:ok, fn candidate, :ok ->
      case GitExclude.ensure_entry(candidate, @workpad_filename) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  def ensure_workpad_ignore(workspace, worker_host, opts)
      when is_binary(workspace) and is_binary(worker_host) and is_list(opts) do
    script =
      [
        "set -eu",
        Paths.remote_shell_assign("workspace", workspace),
        Paths.remote_shell_assign("entry", @workpad_filename),
        "for candidate in \"$workspace\" \"$workspace/repo\"; do",
        "  [ -d \"$candidate\" ] || continue",
        "  exclude=\"\"",
        "  if command -v git >/dev/null 2>&1; then",
        "    git_exclude=$(cd \"$candidate\" && git rev-parse --git-path info/exclude 2>/dev/null || true)",
        "    if [ -n \"$git_exclude\" ]; then",
        "      case \"$git_exclude\" in",
        "        /*) exclude=\"$git_exclude\" ;;",
        "        *) exclude=\"$candidate/$git_exclude\" ;;",
        "      esac",
        "    fi",
        "  fi",
        "  if [ -z \"$exclude\" ] && [ -d \"$candidate/.git\" ]; then",
        "    exclude=\"$candidate/.git/info/exclude\"",
        "  fi",
        "  if [ -n \"$exclude\" ]; then",
        "    mkdir -p \"$(dirname \"$exclude\")\"",
        "    touch \"$exclude\"",
        "    if ! grep -Fqx \"$entry\" \"$exclude\"; then",
        "      printf '\\n%s\\n' \"$entry\" >> \"$exclude\"",
        "    fi",
        "  fi",
        "done"
      ]
      |> Enum.join("\n")

    case remote_runner(worker_host, opts).(script) do
      {:ok, {_output, 0}} -> :ok
      {:ok, {output, status}} -> {:error, {:workspace_prepare_failed, worker_host, status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp remote_runner(worker_host, opts) do
    case Keyword.get(opts, :remote_runner) do
      runner when is_function(runner, 1) ->
        runner

      _runner ->
        timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
        WorkspaceRemote.remote_command_runner(worker_host, timeout_ms)
    end
  end

  defp local_ignore_candidates(workspace), do: [workspace, Path.join(workspace, "repo")]
end
