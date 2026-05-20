defmodule SymphonyElixir.Orchestrator.Running.Termination do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Running.StateView

  @spec terminate_running_issue(map(), String.t(), boolean(), keyword()) :: map()
  def terminate_running_issue(state, issue_id, cleanup_workspace?, opts) when is_binary(issue_id) do
    case Map.get(StateView.running_entries(state), issue_id) do
      nil ->
        release_issue_claim(state, issue_id)

      %{pid: pid, ref: ref, identifier: identifier} = running_entry ->
        state = record_session_completion_totals(state, running_entry, opts)

        if cleanup_workspace? do
          cleanup_workspace(opts, identifier, running_entry)
        end

        cleanup_active_agent_session(opts, pid)
        terminate_task(pid)
        demonitor(ref)

        state
        |> StateView.put_running(Map.delete(StateView.running_entries(state), issue_id))
        |> StateView.put_claimed(MapSet.delete(StateView.claimed_entries(state), issue_id))
        |> StateView.put_retry_attempts(Map.delete(StateView.retry_attempts(state), issue_id))

      _other ->
        release_issue_claim(state, issue_id)
    end
  end

  def terminate_running_issue(state, _issue_id, _cleanup_workspace?, _opts), do: state

  @spec release_issue_claim(map(), String.t()) :: map()
  def release_issue_claim(state, issue_id) when is_binary(issue_id) do
    StateView.put_claimed(state, MapSet.delete(StateView.claimed_entries(state), issue_id))
  end

  def release_issue_claim(state, _issue_id), do: state

  defp terminate_task(pid) when is_pid(pid) do
    case Task.Supervisor.terminate_child(SymphonyElixir.TaskSupervisor, pid) do
      :ok ->
        :ok

      {:error, :not_found} ->
        Process.exit(pid, :shutdown)
    end
  end

  defp terminate_task(_pid), do: :ok

  defp demonitor(ref) when is_reference(ref), do: Process.demonitor(ref, [:flush])
  defp demonitor(_ref), do: :ok

  defp record_session_completion_totals(state, running_entry, opts) when is_map(running_entry) do
    case Keyword.get(opts, :record_session_completion_totals) do
      record_session_completion_totals when is_function(record_session_completion_totals, 2) ->
        case record_session_completion_totals.(state, running_entry) do
          %{} = updated_state -> updated_state
          _other -> state
        end

      _other ->
        state
    end
  end

  defp cleanup_workspace(opts, identifier, running_entry) when is_binary(identifier) do
    case Keyword.get(opts, :cleanup_issue_workspace) do
      cleanup_issue_workspace when is_function(cleanup_issue_workspace, 3) ->
        cleanup_issue_workspace.(
          identifier,
          Map.get(running_entry, :worker_host),
          Map.get(running_entry, :workspace_path)
        )

      _other ->
        :ok
    end
  end

  defp cleanup_workspace(_opts, _identifier, _running_entry), do: :ok

  defp cleanup_active_agent_session(opts, pid) when is_pid(pid) do
    case Keyword.get(opts, :cleanup_active_agent_session) do
      cleanup when is_function(cleanup, 2) -> cleanup.(pid, :running_issue_terminated)
      cleanup when is_function(cleanup, 1) -> cleanup.(pid)
      _cleanup -> :ok
    end
  end

  defp cleanup_active_agent_session(_opts, _pid), do: :ok
end
