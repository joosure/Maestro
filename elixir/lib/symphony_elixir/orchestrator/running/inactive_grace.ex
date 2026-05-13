defmodule SymphonyElixir.Orchestrator.Running.InactiveGrace do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Running.{Events, StateView, Termination}

  @spec reconcile(Issue.t(), map(), keyword()) :: map()
  def reconcile(%Issue{} = issue, state, opts) do
    now = current_time(opts)
    grace_ms = non_active_completion_grace_ms(opts)

    case maybe_defer_non_active_termination(state, issue, now, grace_ms) do
      {:deferred, updated_state, observed_at} ->
        Events.issue_reconcile(opts, :info, :issue_reconcile_deferred, issue, updated_state, %{
          skip_reason: "not_active_completion_grace",
          grace_started_at: observed_at,
          grace_window_ms: grace_ms
        })

        updated_state

      :terminate ->
        Events.issue_reconcile(opts, :info, :issue_reconcile_stopped, issue, state, %{
          skip_reason: "not_active"
        })

        Termination.terminate_running_issue(state, issue.id, false, opts)
    end
  end

  def reconcile(_issue, state, _opts), do: state

  @spec last_activity_timestamp(map()) :: DateTime.t() | nil
  def last_activity_timestamp(running_entry) when is_map(running_entry) do
    Map.get(running_entry, :last_agent_timestamp) || Map.get(running_entry, :started_at)
  end

  def last_activity_timestamp(_running_entry), do: nil

  defp maybe_defer_non_active_termination(state, %Issue{id: issue_id} = issue, now, grace_ms)
       when is_map(state) and is_binary(issue_id) and is_struct(now, DateTime) and
              is_integer(grace_ms) do
    case Map.get(StateView.running_entries(state), issue_id) do
      %{non_active_observed_at: %DateTime{} = observed_at} = running_entry ->
        if grace_active?(observed_at, now, grace_ms) do
          updated_entry = Map.put(running_entry, :issue, issue)
          updated_state = StateView.put_running(state, Map.put(StateView.running_entries(state), issue_id, updated_entry))
          {:deferred, updated_state, observed_at}
        else
          :terminate
        end

      %{issue: _} = running_entry ->
        if recent_agent_activity?(running_entry, now, grace_ms) do
          updated_entry =
            running_entry
            |> Map.put(:issue, issue)
            |> Map.put(:non_active_observed_at, now)

          updated_state = StateView.put_running(state, Map.put(StateView.running_entries(state), issue_id, updated_entry))
          {:deferred, updated_state, now}
        else
          :terminate
        end

      _other ->
        :terminate
    end
  end

  defp maybe_defer_non_active_termination(_state, _issue, _now, _grace_ms), do: :terminate

  defp recent_agent_activity?(running_entry, now, grace_ms)
       when is_map(running_entry) and is_struct(now, DateTime) and is_integer(grace_ms) do
    case last_activity_timestamp(running_entry) do
      %DateTime{} = timestamp when grace_ms > 0 ->
        DateTime.diff(now, timestamp, :millisecond) <= grace_ms

      _other ->
        false
    end
  end

  defp recent_agent_activity?(_running_entry, _now, _grace_ms), do: false

  defp grace_active?(observed_at, now, grace_ms)
       when is_struct(observed_at, DateTime) and is_struct(now, DateTime) and is_integer(grace_ms) do
    grace_ms > 0 and DateTime.diff(now, observed_at, :millisecond) < grace_ms
  end

  defp grace_active?(_observed_at, _now, _grace_ms), do: false

  defp non_active_completion_grace_ms(opts) do
    case Keyword.get(opts, :non_active_completion_grace_ms, 0) do
      value when is_integer(value) and value > 0 -> value
      _other -> 0
    end
  end

  defp current_time(opts) do
    case Keyword.get(opts, :now) do
      %DateTime{} = now -> now
      _other -> DateTime.utc_now()
    end
  end
end
