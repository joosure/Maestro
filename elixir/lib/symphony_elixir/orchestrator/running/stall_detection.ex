defmodule SymphonyElixir.Orchestrator.Running.StallDetection do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Retry
  alias SymphonyElixir.Orchestrator.Running.{CompletionGrace, Events, StateView, Termination}

  @spec reconcile_stalled(map(), integer(), keyword()) :: map()
  def reconcile_stalled(state, timeout_ms, opts)
      when is_map(state) and is_integer(timeout_ms) do
    cond do
      timeout_ms <= 0 ->
        state

      map_size(StateView.running_entries(state)) == 0 ->
        state

      true ->
        now = current_time(opts)

        Enum.reduce(StateView.running_entries(state), state, fn {issue_id, running_entry}, state_acc ->
          restart_stalled_issue(state_acc, issue_id, running_entry, now, timeout_ms, opts)
        end)
    end
  end

  def reconcile_stalled(state, _timeout_ms, _opts), do: state

  defp restart_stalled_issue(state, issue_id, running_entry, now, timeout_ms, opts) do
    elapsed_ms = stall_elapsed_ms(running_entry, now)

    if is_integer(elapsed_ms) and elapsed_ms > timeout_ms do
      identifier = Map.get(running_entry, :identifier, issue_id)
      session_id = running_entry_session_id(running_entry)

      Events.emit(opts, :warning, :issue_stall_detected, Map.get(running_entry, :issue), state, %{
        issue_id: issue_id,
        issue_identifier: identifier,
        session_id: session_id,
        duration_ms: elapsed_ms
      })

      next_attempt = Retry.next_attempt_from_running(running_entry)

      state
      |> Termination.terminate_running_issue(issue_id, false, opts)
      |> schedule_retry(
        issue_id,
        next_attempt,
        %{
          identifier: identifier,
          error: "stalled for #{elapsed_ms}ms without agent activity"
        },
        opts
      )
    else
      state
    end
  end

  defp stall_elapsed_ms(running_entry, now) do
    running_entry
    |> CompletionGrace.last_activity_timestamp()
    |> case do
      %DateTime{} = timestamp ->
        max(0, DateTime.diff(now, timestamp, :millisecond))

      _other ->
        nil
    end
  end

  defp running_entry_session_id(%{session_id: session_id}) when is_binary(session_id),
    do: session_id

  defp running_entry_session_id(_running_entry), do: "n/a"

  defp schedule_retry(state, issue_id, attempt, metadata, opts)
       when is_binary(issue_id) and is_map(metadata) do
    case Keyword.get(opts, :schedule_retry) do
      schedule_retry when is_function(schedule_retry, 4) ->
        case schedule_retry.(state, issue_id, attempt, metadata) do
          %{} = updated_state -> updated_state
          _other -> state
        end

      _other ->
        state
    end
  end

  defp schedule_retry(state, _issue_id, _attempt, _metadata, _opts), do: state

  defp current_time(opts) do
    case Keyword.get(opts, :now) do
      %DateTime{} = now -> now
      _other -> DateTime.utc_now()
    end
  end
end
