defmodule SymphonyElixir.Orchestrator.WorkerExit do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Events
  alias SymphonyElixir.Orchestrator.Retry
  alias SymphonyElixir.Orchestrator.Retry.ResultSummary
  alias SymphonyElixir.Orchestrator.Retry.Status, as: RetryStatus
  alias SymphonyElixir.Orchestrator.RunningState
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyWorkerDaemon.Session.Status, as: WorkerSessionStatus

  def handle_down_message(state, ref, reason, opts \\ [])

  @spec handle_down_message(State.t(), reference(), term(), keyword()) :: {:noreply, State.t()}
  def handle_down_message(%State{} = state, ref, reason, opts) when is_reference(ref) do
    case handle_worker_exit(state, ref, reason) do
      :unknown ->
        {:noreply, state}

      {:ok, state} ->
        notify_dashboard(opts)
        {:noreply, state}
    end
  end

  def handle_down_message(%State{} = state, _ref, _reason, _opts), do: {:noreply, state}

  defp handle_worker_exit(%State{running: running} = state, ref, reason) when is_reference(ref) do
    case find_issue_id_for_ref(running, ref) do
      nil ->
        :unknown

      issue_id ->
        {running_entry, state} = pop_running_entry(state, issue_id)
        state = RunningState.record_session_completion(state, running_entry)
        {:ok, handle_exit_reason(state, issue_id, running_entry, reason)}
    end
  end

  defp notify_dashboard(opts) do
    case Keyword.get(opts, :notify_dashboard) do
      notify_dashboard when is_function(notify_dashboard, 0) -> notify_dashboard.()
      _other -> :ok
    end
  end

  defp handle_exit_reason(state, issue_id, running_entry, :normal) do
    Events.emit_issue_worker_finished(
      state,
      issue_id,
      running_entry,
      :normal,
      "completed",
      ResultSummary.continuation_scheduled()
    )

    state
    |> complete_issue(issue_id)
    |> Retry.schedule(
      issue_id,
      1,
      %{
        identifier: running_entry.identifier,
        delay_type: :continuation,
        run_id: Map.get(running_entry, :run_id),
        worker_host: Map.get(running_entry, :worker_host),
        workspace_path: Map.get(running_entry, :workspace_path),
        agent_provider_kind: Map.get(running_entry, :agent_provider_kind),
        failure_class: Map.get(running_entry, :failure_class)
      },
      emit_event: &Events.emit/5
    )
  end

  defp handle_exit_reason(state, issue_id, running_entry, reason) do
    Events.emit_issue_worker_finished(
      state,
      issue_id,
      running_entry,
      reason,
      WorkerSessionStatus.exited(),
      RetryStatus.retry_scheduled()
    )

    next_attempt = Retry.next_attempt_from_running(running_entry)

    Retry.schedule(
      state,
      issue_id,
      next_attempt,
      %{
        identifier: running_entry.identifier,
        error: "agent exited: #{inspect(reason)}",
        run_id: Map.get(running_entry, :run_id),
        agent_provider_kind: Map.get(running_entry, :agent_provider_kind),
        worker_host: Map.get(running_entry, :worker_host),
        workspace_path: Map.get(running_entry, :workspace_path),
        failure_class: Map.get(running_entry, :failure_class)
      },
      emit_event: &Events.emit/5
    )
  end

  defp find_issue_id_for_ref(running, ref) do
    running
    |> Enum.find_value(fn {issue_id, %{ref: running_ref}} ->
      if running_ref == ref, do: issue_id
    end)
  end

  defp pop_running_entry(state, issue_id) do
    {Map.get(state.running, issue_id), %{state | running: Map.delete(state.running, issue_id)}}
  end

  defp complete_issue(%State{} = state, issue_id) do
    %{
      state
      | completed: MapSet.put(state.completed, issue_id),
        retry_attempts: Map.delete(state.retry_attempts, issue_id)
    }
  end
end
