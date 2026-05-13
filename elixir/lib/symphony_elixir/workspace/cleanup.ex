defmodule SymphonyElixir.Workspace.Cleanup do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Workspace.Context
  alias SymphonyElixir.Workspace.Hooks
  alias SymphonyElixir.Workspace.Paths

  @type worker_host :: String.t() | nil
  @type hooks_config :: map()
  @type event_fields_builder :: (map(), Path.t() | nil, worker_host(), map() -> map())
  @type remote_runner :: (String.t() -> {:ok, {term(), integer()}} | {:error, term()})
  @type remote_runner_factory :: (String.t() -> remote_runner())

  @spec remove(Path.t(), worker_host(), Path.t() | nil, keyword()) ::
          {:ok, [String.t()]} | {:error, term(), String.t()}
  def remove(workspace, nil, workspace_root_override, opts)
      when is_binary(workspace) and is_list(opts) do
    issue_context = Context.workspace_context(workspace)
    workspace_root = configured_workspace_root(opts, workspace_root_override)

    case File.exists?(workspace) do
      true ->
        case Paths.validate_local_workspace_path(workspace, workspace_root) do
          :ok ->
            maybe_run_before_remove_hook(workspace, nil, opts)
            remove_local_workspace(workspace, issue_context, opts)

          {:error, reason} ->
            emit_event(
              :error,
              :workspace_remove_failed,
              issue_context,
              workspace,
              nil,
              %{error: inspect(reason)},
              opts
            )

            {:error, reason, ""}
        end

      false ->
        remove_local_workspace(workspace, issue_context, opts)
    end
  end

  def remove(workspace, worker_host, workspace_root_override, opts)
      when is_binary(workspace) and is_binary(worker_host) and is_list(opts) do
    issue_context = Context.workspace_context(workspace)
    remote_runner = remote_runner_factory(opts).(worker_host)

    case Paths.resolve_remote_workspace_for_cleanup(
           workspace,
           worker_host,
           configured_workspace_root(opts, workspace_root_override),
           remote_runner
         ) do
      {:ok, :missing} ->
        emit_event(
          :info,
          :workspace_removed,
          issue_context,
          workspace,
          worker_host,
          %{result_summary: "missing"},
          opts
        )

        {:ok, []}

      {:ok, %{workspace: resolved_workspace, directory?: directory?}} ->
        if directory? do
          maybe_run_before_remove_hook(resolved_workspace, worker_host, opts)
        end

        script =
          [
            Paths.remote_shell_assign("workspace", resolved_workspace),
            "rm -rf \"$workspace\""
          ]
          |> Enum.join("\n")

        case remote_runner.(script) do
          {:ok, {_output, 0}} ->
            emit_event(
              :info,
              :workspace_removed,
              issue_context,
              resolved_workspace,
              worker_host,
              %{result_summary: "removed"},
              opts
            )

            {:ok, []}

          {:ok, {output, status}} ->
            emit_event(
              :error,
              :workspace_remove_failed,
              issue_context,
              resolved_workspace,
              worker_host,
              %{
                error: "status=#{status}",
                payload_summary: Hooks.sanitize_output_for_log(output)
              },
              opts
            )

            {:error, {:workspace_remove_failed, worker_host, status, output}, ""}

          {:error, reason} ->
            emit_event(
              :error,
              :workspace_remove_failed,
              issue_context,
              resolved_workspace,
              worker_host,
              %{error: inspect(reason)},
              opts
            )

            {:error, reason, ""}
        end

      {:error, reason} ->
        emit_event(
          :error,
          :workspace_remove_failed,
          issue_context,
          workspace,
          worker_host,
          %{error: inspect(reason)},
          opts
        )

        {:error, reason, ""}
    end
  end

  @spec remove_issue_workspaces(term(), worker_host(), Path.t() | nil, keyword()) :: :ok
  def remove_issue_workspaces(identifier, worker_host, workspace_path, opts)
      when is_binary(identifier) and is_binary(worker_host) and is_binary(workspace_path) and
             is_list(opts) do
    remove(workspace_path, worker_host, Path.dirname(workspace_path), opts)
    :ok
  end

  def remove_issue_workspaces(identifier, worker_host, nil, opts)
      when is_binary(identifier) and is_binary(worker_host) and is_list(opts) do
    safe_id = Paths.safe_identifier(identifier)

    case Paths.workspace_path_for_issue(safe_id, workspace_root(opts), worker_host) do
      {:ok, workspace} -> remove(workspace, worker_host, nil, opts)
      {:error, _reason} -> :ok
    end

    :ok
  end

  def remove_issue_workspaces(identifier, nil, workspace_path, opts)
      when is_binary(identifier) and is_binary(workspace_path) and is_list(opts) do
    remove(workspace_path, nil, Path.dirname(workspace_path), opts)
    :ok
  end

  def remove_issue_workspaces(identifier, nil, nil, opts)
      when is_binary(identifier) and is_list(opts) do
    safe_id = Paths.safe_identifier(identifier)

    case ssh_hosts(opts) do
      [] ->
        case Paths.workspace_path_for_issue(safe_id, workspace_root(opts), nil) do
          {:ok, workspace} -> remove(workspace, nil, nil, opts)
          {:error, _reason} -> :ok
        end

      worker_hosts ->
        Enum.each(worker_hosts, &remove_issue_workspaces(identifier, &1, nil, opts))
    end

    :ok
  end

  def remove_issue_workspaces(_identifier, _worker_host, _workspace_path, _opts), do: :ok

  defp remove_local_workspace(workspace, issue_context, opts) do
    case File.rm_rf(workspace) do
      {:ok, entries} = result ->
        emit_event(
          :info,
          :workspace_removed,
          issue_context,
          workspace,
          nil,
          %{result_summary: "removed_entries=#{length(entries)}"},
          opts
        )

        result

      {:error, reason, _file} = error ->
        emit_event(
          :error,
          :workspace_remove_failed,
          issue_context,
          workspace,
          nil,
          %{error: inspect(reason)},
          opts
        )

        error
    end
  end

  defp maybe_run_before_remove_hook(workspace, nil, opts) do
    Hooks.maybe_run_before_remove(workspace, hooks_config(opts), nil, hook_opts(nil, opts))
  end

  defp maybe_run_before_remove_hook(workspace, worker_host, opts) when is_binary(worker_host) do
    Hooks.maybe_run_before_remove(
      workspace,
      hooks_config(opts),
      worker_host,
      hook_opts(worker_host, opts)
    )
  end

  defp emit_event(level, event, issue_context, workspace, worker_host, extra_fields, opts) do
    ObsLogger.emit(
      level,
      event,
      event_fields_builder(opts).(issue_context, workspace, worker_host, extra_fields)
    )
  end

  defp hook_opts(nil, opts), do: [event_fields: event_fields_builder(opts)]

  defp hook_opts(worker_host, opts) when is_binary(worker_host) do
    [
      event_fields: event_fields_builder(opts),
      remote_runner: remote_runner_factory(opts).(worker_host)
    ]
  end

  defp configured_workspace_root(opts, nil), do: workspace_root(opts)
  defp configured_workspace_root(_opts, workspace_root) when is_binary(workspace_root), do: workspace_root

  defp hooks_config(opts), do: Keyword.fetch!(opts, :hooks)
  defp event_fields_builder(opts), do: Keyword.fetch!(opts, :event_fields)
  defp remote_runner_factory(opts), do: Keyword.fetch!(opts, :remote_runner)
  defp workspace_root(opts), do: Keyword.fetch!(opts, :workspace_root)
  defp ssh_hosts(opts), do: Keyword.fetch!(opts, :ssh_hosts)
end
