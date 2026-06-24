defmodule SymphonyElixir.Orchestrator.WorkerExit do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.EventContract, as: DynamicToolEventContract
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Orchestrator.BlockedResourceRegistry
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Events
  alias SymphonyElixir.Orchestrator.Retry
  alias SymphonyElixir.Orchestrator.Retry.ResultSummary
  alias SymphonyElixir.Orchestrator.Retry.Status, as: RetryStatus
  alias SymphonyElixir.Orchestrator.RunningState
  alias SymphonyElixir.Orchestrator.Runtime
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyWorkerDaemon.Session.Status, as: WorkerSessionStatus

  @default_issue_refresh_timeout_ms 2_000
  @default_issue_fact_freshness_ms 10_000

  def handle_down_message(state, ref, reason, opts \\ [])

  @spec handle_down_message(State.t(), reference(), term(), keyword()) :: {:noreply, State.t()}
  def handle_down_message(%State{} = state, ref, reason, opts) when is_reference(ref) do
    case handle_worker_exit(state, ref, reason, opts) do
      :unknown ->
        {:noreply, state}

      {:ok, state} ->
        notify_dashboard(opts)
        {:noreply, state}
    end
  end

  def handle_down_message(%State{} = state, _ref, _reason, _opts), do: {:noreply, state}

  defp handle_worker_exit(%State{running: running} = state, ref, reason, opts) when is_reference(ref) do
    case find_issue_id_for_ref(running, ref) do
      nil ->
        :unknown

      issue_id ->
        {running_entry, state} = pop_running_entry(state, issue_id)
        state = RunningState.record_session_completion(state, running_entry)
        {:ok, handle_exit_reason(state, issue_id, running_entry, reason, opts)}
    end
  end

  defp refresh_exit_issue_state(state, issue_id, running_entry, opts) when is_binary(issue_id) and is_map(running_entry) do
    if fresh_running_issue_fact?(running_entry, opts) do
      running_entry
    else
      do_refresh_exit_issue_state(state, issue_id, running_entry, opts)
    end
  end

  defp refresh_exit_issue_state(_state, _issue_id, running_entry, _opts), do: running_entry

  defp fresh_running_issue_fact?(%{issue: %Issue{}, issue_fact_updated_at_ms: updated_at_ms}, opts)
       when is_integer(updated_at_ms) do
    monotonic_ms(opts) - updated_at_ms <= issue_fact_freshness_ms(opts)
  end

  defp fresh_running_issue_fact?(_running_entry, _opts), do: false

  defp do_refresh_exit_issue_state(state, issue_id, running_entry, opts) do
    case Keyword.get(opts, :fetch_issue_states_by_ids) do
      fetch_issue_states_by_ids when is_function(fetch_issue_states_by_ids, 1) ->
        timeout_ms = issue_refresh_timeout_ms(opts)

        with {:ok, issues} when is_list(issues) <- bounded_fetch_issue_states(fetch_issue_states_by_ids, issue_id, timeout_ms),
             %Issue{} = refreshed_issue <- find_refreshed_issue(issues, issue_id) do
          Map.put(running_entry, :issue, refreshed_issue)
        else
          {:error, reason} ->
            emit_issue_refresh_failed(state, issue_id, running_entry, reason)
            running_entry

          _other ->
            running_entry
        end

      _other ->
        running_entry
    end
  end

  defp bounded_fetch_issue_states(fetch_issue_states_by_ids, issue_id, timeout_ms) do
    task = start_issue_refresh_task(fn -> safe_fetch_issue_states(fetch_issue_states_by_ids, issue_id) end)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:worker_exit_issue_refresh_timeout, timeout_ms}}
    end
  end

  defp start_issue_refresh_task(fun) when is_function(fun, 0) do
    case Process.whereis(SymphonyElixir.TaskSupervisor) do
      pid when is_pid(pid) -> Task.Supervisor.async_nolink(SymphonyElixir.TaskSupervisor, fun)
      _other -> Task.async(fun)
    end
  end

  defp safe_fetch_issue_states(fetch_issue_states_by_ids, issue_id) do
    fetch_issue_states_by_ids.([issue_id])
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp issue_refresh_timeout_ms(opts) do
    case Keyword.get(opts, :issue_refresh_timeout_ms, @default_issue_refresh_timeout_ms) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> timeout_ms
      _other -> @default_issue_refresh_timeout_ms
    end
  end

  defp issue_fact_freshness_ms(opts) do
    case Keyword.get(opts, :issue_fact_freshness_ms, @default_issue_fact_freshness_ms) do
      freshness_ms when is_integer(freshness_ms) and freshness_ms > 0 -> freshness_ms
      _other -> @default_issue_fact_freshness_ms
    end
  end

  defp monotonic_ms(opts) do
    case Keyword.get(opts, :monotonic_ms) do
      monotonic_ms when is_integer(monotonic_ms) -> monotonic_ms
      _other -> System.monotonic_time(:millisecond)
    end
  end

  defp emit_issue_refresh_failed(state, issue_id, running_entry, reason) do
    issue = Map.get(running_entry, :issue)

    Events.emit(:warning, :worker_exit_issue_refresh_failed, issue, state, %{
      issue_id: issue_id,
      issue_identifier: Map.get(running_entry, :identifier),
      run_id: Map.get(running_entry, :run_id),
      session_id: Map.get(running_entry, :session_id),
      current_state: issue && issue.state,
      error: inspect(reason),
      result_summary: "exit_issue_refresh_skipped",
      message: "worker_exit_issue_refresh_failed issue_id=#{issue_id} issue_identifier=#{Map.get(running_entry, :identifier)} error=#{inspect(reason)}"
    })
  end

  defp find_refreshed_issue(issues, issue_id) do
    Enum.find(issues, fn
      %Issue{id: ^issue_id} -> true
      _other -> false
    end)
  end

  defp notify_dashboard(opts) do
    case Keyword.get(opts, :notify_dashboard) do
      notify_dashboard when is_function(notify_dashboard, 0) -> notify_dashboard.()
      _other -> :ok
    end
  end

  defp handle_exit_reason(state, issue_id, running_entry, :normal, opts) do
    case non_retryable_typed_tool_blocker(issue_id, running_entry) do
      %{} = blocker ->
        suppress_retry_after_typed_tool_blocker(state, issue_id, running_entry, :normal, blocker)

      nil ->
        running_entry = refresh_exit_issue_state(state, issue_id, running_entry, opts)
        continue_after_normal_exit(state, issue_id, running_entry)
    end
  end

  defp handle_exit_reason(state, issue_id, running_entry, reason, opts) do
    case non_retryable_typed_tool_blocker(issue_id, running_entry) do
      %{} = blocker ->
        suppress_retry_after_typed_tool_blocker(state, issue_id, running_entry, reason, blocker)

      nil ->
        running_entry = refresh_exit_issue_state(state, issue_id, running_entry, opts)

        case retry_suppression_decision(issue_id, running_entry) do
          {:suppress, refreshed_issue, skip_reason} ->
            suppress_retry_after_handoff(state, issue_id, running_entry, reason, refreshed_issue, skip_reason)

          :schedule_retry ->
            schedule_failure_retry(state, issue_id, running_entry, reason)
        end
    end
  end

  defp suppress_retry_after_typed_tool_blocker(state, issue_id, running_entry, reason, blocker) do
    issue = Map.get(running_entry, :issue)
    register_typed_tool_blocker(issue_id, running_entry, blocker)

    Events.emit_issue_worker_finished(
      state,
      issue_id,
      running_entry,
      reason,
      WorkerSessionStatus.exited(),
      ResultSummary.retry_suppressed_blocked()
    )

    Events.emit(
      :warning,
      :agent_run_retry_suppressed,
      issue,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: Map.get(running_entry, :identifier),
        run_id: Map.get(running_entry, :run_id),
        session_id: Map.get(running_entry, :session_id),
        current_state: issue && issue.state,
        skip_reason: "typed_tool_non_retryable_blocker",
        result_summary: ResultSummary.retry_suppressed_blocked(),
        error: inspect(reason),
        blocker_error_code: Map.get(blocker, "error_code"),
        blocker_original_error_code: Map.get(blocker, "original_error_code"),
        blocker_tool_name: Map.get(blocker, "tool_name"),
        blocker_resource_kind: Map.get(blocker, "resource_kind"),
        blocker_resource_id: Map.get(blocker, "resource_id"),
        agent_provider_kind: Map.get(running_entry, :agent_provider_kind),
        worker_host: Map.get(running_entry, :worker_host),
        workspace_path: Map.get(running_entry, :workspace_path),
        failure_class: "typed_tool_non_retryable_blocker",
        message: "agent_run_retry_suppressed issue_id=#{issue_id} issue_identifier=#{Map.get(running_entry, :identifier)} skip_reason=typed_tool_non_retryable_blocker"
      }
    )

    complete_issue(state, issue_id)
  end

  defp register_typed_tool_blocker(issue_id, running_entry, blocker) do
    attrs = %{
      "resource_kind" => Map.get(blocker, "resource_kind") || "tracker_issue",
      "resource_id" => Map.get(blocker, "resource_id") || issue_id,
      "issue_identifier" => Map.get(running_entry, :identifier),
      "run_id" => Map.get(running_entry, :run_id),
      "session_id" => Map.get(running_entry, :session_id),
      "tool_name" => Map.get(blocker, "tool_name"),
      "blocker_code" => Map.get(blocker, "error_code"),
      "original_error_code" => Map.get(blocker, "original_error_code")
    }

    case BlockedResourceRegistry.register(attrs) do
      {:ok, _record} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp schedule_failure_retry(state, issue_id, running_entry, reason) do
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

  defp suppress_retry_after_handoff(state, issue_id, running_entry, reason, refreshed_issue, skip_reason) do
    refreshed_running_entry = Map.put(running_entry, :issue, refreshed_issue)

    Events.emit_issue_worker_finished(
      state,
      issue_id,
      refreshed_running_entry,
      reason,
      WorkerSessionStatus.exited(),
      ResultSummary.retry_suppressed_non_dispatchable()
    )

    Events.emit(
      :info,
      :agent_run_retry_suppressed,
      refreshed_issue,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: refreshed_running_entry.identifier,
        run_id: Map.get(refreshed_running_entry, :run_id),
        session_id: Map.get(refreshed_running_entry, :session_id),
        current_state: refreshed_issue.state,
        skip_reason: skip_reason,
        result_summary: ResultSummary.retry_suppressed_non_dispatchable(),
        error: inspect(reason),
        agent_provider_kind: Map.get(refreshed_running_entry, :agent_provider_kind),
        worker_host: Map.get(refreshed_running_entry, :worker_host),
        workspace_path: Map.get(refreshed_running_entry, :workspace_path),
        failure_class: Map.get(refreshed_running_entry, :failure_class) || "agent_run_failure",
        message: "agent_run_retry_suppressed issue_id=#{issue_id} issue_identifier=#{refreshed_running_entry.identifier} current_state=#{inspect(refreshed_issue.state)} skip_reason=#{skip_reason}"
      }
    )

    complete_issue(state, issue_id)
  end

  defp continue_after_normal_exit(state, issue_id, running_entry) do
    case continuation_decision(issue_id, running_entry) do
      :continue ->
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

      {:suppress, refreshed_issue, skip_reason} ->
        suppress_continuation_after_completion(state, issue_id, running_entry, refreshed_issue, skip_reason)
    end
  end

  defp suppress_continuation_after_completion(state, issue_id, running_entry, refreshed_issue, skip_reason) do
    refreshed_running_entry = Map.put(running_entry, :issue, refreshed_issue)

    Events.emit_issue_worker_finished(
      state,
      issue_id,
      refreshed_running_entry,
      :normal,
      "completed",
      ResultSummary.continuation_suppressed_non_dispatchable()
    )

    Events.emit(
      :info,
      :agent_run_continuation_suppressed,
      refreshed_issue,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: refreshed_running_entry.identifier,
        run_id: Map.get(refreshed_running_entry, :run_id),
        session_id: Map.get(refreshed_running_entry, :session_id),
        current_state: refreshed_issue.state,
        skip_reason: skip_reason,
        result_summary: ResultSummary.continuation_suppressed_non_dispatchable(),
        agent_provider_kind: Map.get(refreshed_running_entry, :agent_provider_kind),
        worker_host: Map.get(refreshed_running_entry, :worker_host),
        workspace_path: Map.get(refreshed_running_entry, :workspace_path),
        failure_class: Map.get(refreshed_running_entry, :failure_class),
        message:
          "agent_run_continuation_suppressed issue_id=#{issue_id} issue_identifier=#{refreshed_running_entry.identifier} current_state=#{inspect(refreshed_issue.state)} skip_reason=#{skip_reason}"
      }
    )

    complete_issue(state, issue_id)
  end

  defp retry_suppression_decision(issue_id, running_entry) when is_binary(issue_id) and is_map(running_entry) do
    dispatch_context = Runtime.dispatch_context()
    retry_suppression_decision_for_issue(issue_id, running_entry, dispatch_context)
  end

  defp retry_suppression_decision(_issue_id, _running_entry), do: :schedule_retry

  defp continuation_decision(issue_id, running_entry) when is_binary(issue_id) and is_map(running_entry) do
    case Map.get(running_entry, :issue) do
      %SymphonyElixir.Issue{} = issue ->
        dispatch_context = Runtime.dispatch_context()

        if retryable_running_issue?(issue, dispatch_context) do
          :continue
        else
          {:suppress, issue, retry_suppression_reason(issue, dispatch_context)}
        end

      _other ->
        :continue
    end
  end

  defp continuation_decision(_issue_id, _running_entry), do: :continue

  defp retry_suppression_decision_for_issue(_issue_id, running_entry, dispatch_context) do
    case Map.get(running_entry, :issue) do
      %SymphonyElixir.Issue{} = issue ->
        if retryable_running_issue?(issue, dispatch_context) do
          :schedule_retry
        else
          {:suppress, issue, retry_suppression_reason(issue, dispatch_context)}
        end

      _other ->
        :schedule_retry
    end
  end

  defp non_retryable_typed_tool_blocker(issue_id, running_entry) do
    run_id = Map.get(running_entry, :run_id)

    %{issue_id: issue_id, run_id: run_id}
    |> EventStore.recent_issue_events(limit: 100)
    |> Enum.find(fn event ->
      event["event"] == DynamicToolEventContract.typed_tool_failure_policy_blocked() and
        event["retryable"] == false and
        event["resource_kind"] == "tracker_issue" and
        event["resource_id"] == issue_id and
        (is_nil(run_id) or event["run_id"] == run_id)
    end)
  end

  defp retryable_running_issue?(issue, dispatch_context) do
    Dispatch.issue_routable_to_worker?(issue) and
      Dispatch.active_issue_state?(issue, issue.state, dispatch_context) and
      not Dispatch.terminal_issue_state?(issue, issue.state, dispatch_context)
  end

  defp retry_suppression_reason(refreshed_issue, dispatch_context) do
    runtime = %{
      running: %{},
      claimed: [],
      orchestrator_slots: 1,
      worker_slots_available?: true
    }

    refreshed_issue
    |> Dispatch.dispatch_skip_reason(runtime, dispatch_context)
    |> case do
      nil -> "not_retry_candidate"
      reason -> Atom.to_string(reason)
    end
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
        claimed: MapSet.delete(state.claimed, issue_id),
        retry_attempts: Map.delete(state.retry_attempts, issue_id)
    }
  end
end
