defmodule SymphonyElixir.Workspace do
  @moduledoc """
  Creates isolated per-issue workspaces for parallel agent runs.
  """

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Tracker

  alias SymphonyElixir.Workspace.Bootstrap
  alias SymphonyElixir.Workspace.Cleanup
  alias SymphonyElixir.Workspace.Context
  alias SymphonyElixir.Workspace.Hooks
  alias SymphonyElixir.Workspace.Paths
  alias SymphonyElixir.Workspace.Remote

  @type worker_host :: String.t() | nil

  @spec create_for_issue(map() | String.t() | nil, worker_host()) ::
          {:ok, Path.t()} | {:error, term()}
  def create_for_issue(issue_or_identifier, worker_host \\ nil) do
    issue_context = Context.issue_context(issue_or_identifier)
    workspace_root = Config.settings!().workspace.root

    try do
      safe_id = Paths.safe_identifier(issue_context.issue_identifier)
      workspace_hint = Paths.workspace_path_hint(safe_id, workspace_root, worker_host)

      ObsLogger.emit(
        :info,
        :workspace_prepare_started,
        Context.event_fields(issue_context, workspace_hint, worker_host)
      )

      with {:ok, workspace} <- Paths.workspace_path_for_issue(safe_id, workspace_root, worker_host),
           :ok <- validate_workspace_path(workspace, worker_host, workspace_root),
           {:ok, workspace, created?} <- ensure_workspace(workspace, worker_host),
           :ok <- maybe_bootstrap_workspace_automation(workspace, issue_context, created?, worker_host),
           :ok <- maybe_run_after_create_hook(workspace, issue_context, created?, worker_host),
           :ok <- maybe_prepare_agent_provider_workspace(workspace, issue_context, worker_host),
           :ok <- maybe_prepare_tracker_workspace(workspace, worker_host) do
        ObsLogger.emit(
          :info,
          :workspace_prepare_succeeded,
          Context.event_fields(issue_context, workspace, worker_host, %{
            result_summary: if(created?, do: "created", else: "reused")
          })
        )

        {:ok, workspace}
      else
        {:error, reason} = error ->
          ObsLogger.emit(
            :error,
            :workspace_prepare_failed,
            Context.event_fields(issue_context, workspace_hint, worker_host, %{
              error: inspect(reason)
            })
          )

          error
      end
    rescue
      error in [ArgumentError, ErlangError, File.Error] ->
        ObsLogger.emit(
          :error,
          :workspace_prepare_failed,
          Context.event_fields(
            issue_context,
            nil,
            worker_host,
            ObsLogger.error_details(error, __STACKTRACE__)
          )
        )

        {:error, error}
    end
  end

  defp ensure_workspace(workspace, nil) do
    cond do
      File.dir?(workspace) ->
        {:ok, workspace, false}

      File.exists?(workspace) ->
        File.rm_rf!(workspace)
        create_workspace(workspace)

      true ->
        create_workspace(workspace)
    end
  end

  defp ensure_workspace(workspace, worker_host) when is_binary(worker_host) do
    Paths.ensure_remote_workspace(
      workspace,
      Config.settings!().workspace.root,
      worker_host,
      Remote.remote_command_runner(worker_host, Config.settings!().hooks.timeout_ms)
    )
  end

  defp create_workspace(workspace) do
    File.rm_rf!(workspace)
    File.mkdir_p!(workspace)
    {:ok, workspace, true}
  end

  @spec remove(Path.t()) :: {:ok, [String.t()]} | {:error, term(), String.t()}
  def remove(workspace), do: remove(workspace, nil)

  @spec remove(Path.t(), worker_host()) :: {:ok, [String.t()]} | {:error, term(), String.t()}
  def remove(workspace, nil), do: Cleanup.remove(workspace, nil, nil, cleanup_opts())

  def remove(workspace, worker_host) when is_binary(worker_host),
    do: Cleanup.remove(workspace, worker_host, nil, cleanup_opts())

  @spec remove_issue_workspaces(term()) :: :ok
  def remove_issue_workspaces(identifier), do: remove_issue_workspaces(identifier, nil, nil)

  @spec remove_issue_workspaces(term(), worker_host()) :: :ok
  def remove_issue_workspaces(identifier, worker_host),
    do: remove_issue_workspaces(identifier, worker_host, nil)

  @spec remove_issue_workspaces(term(), worker_host(), Path.t() | nil) :: :ok
  def remove_issue_workspaces(identifier, worker_host, workspace_path),
    do: Cleanup.remove_issue_workspaces(identifier, worker_host, workspace_path, cleanup_opts())

  @spec run_before_run_hook(Path.t(), map() | String.t() | nil, worker_host()) ::
          :ok | {:error, term()}
  def run_before_run_hook(workspace, issue_or_identifier, worker_host \\ nil) when is_binary(workspace) do
    Hooks.run_before_run(
      workspace,
      Context.issue_context(issue_or_identifier),
      Config.settings!().hooks,
      worker_host,
      workspace_options(worker_host)
    )
  end

  @spec run_after_run_hook(Path.t(), map() | String.t() | nil, worker_host()) :: :ok
  def run_after_run_hook(workspace, issue_or_identifier, worker_host \\ nil) when is_binary(workspace) do
    Hooks.run_after_run(
      workspace,
      Context.issue_context(issue_or_identifier),
      Config.settings!().hooks,
      worker_host,
      workspace_options(worker_host)
    )
  end

  defp maybe_run_after_create_hook(workspace, issue_context, created?, worker_host) do
    Hooks.maybe_run_after_create(
      workspace,
      issue_context,
      created?,
      Config.settings!().hooks,
      worker_host,
      workspace_options(worker_host)
    )
  end

  defp maybe_bootstrap_workspace_automation(workspace, issue_context, created?, worker_host) do
    Bootstrap.maybe_bootstrap_automation_pack(
      workspace,
      issue_context,
      created?,
      Config.settings!().workspace.bootstrap_automation_from,
      worker_host,
      workspace_options(worker_host)
    )
  end

  defp maybe_prepare_tracker_workspace(workspace, worker_host) do
    Tracker.prepare_workspace(workspace, worker_host, workspace_options(worker_host))
  end

  defp maybe_prepare_agent_provider_workspace(workspace, issue_context, worker_host) do
    AgentProvider.prepare_workspace(
      workspace,
      [
        worker_host: worker_host,
        run_id: issue_context[:run_id],
        issue_id: issue_context[:issue_id],
        issue_identifier: issue_context[:issue_identifier]
      ] ++ workspace_options(worker_host)
    )
  end

  defp validate_workspace_path(workspace, nil, workspace_root)
       when is_binary(workspace) and is_binary(workspace_root) do
    Paths.validate_local_workspace_path(workspace, workspace_root)
  end

  defp validate_workspace_path(workspace, worker_host, _workspace_root)
       when is_binary(workspace) and is_binary(worker_host) do
    Paths.validate_remote_workspace_path(workspace, worker_host)
  end

  defp workspace_options(worker_host) do
    Remote.workspace_options(
      worker_host,
      &Context.event_fields/4,
      Config.settings!().hooks.timeout_ms
    )
  end

  defp cleanup_opts do
    Remote.cleanup_options(Config.settings!(), &Context.event_fields/4)
  end
end
