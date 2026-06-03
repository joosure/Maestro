defmodule SymphonyElixir.Orchestrator.Running.CompletionGrace do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Running.{Events, StateView, Termination}

  @observed_at_key :completion_grace_observed_at

  @spec reconcile(Issue.t(), map(), keyword(), keyword()) :: map()
  def reconcile(issue, state, opts, policy_opts \\ [])

  def reconcile(%Issue{} = issue, state, opts, policy_opts) do
    now = current_time(opts)
    grace_ms = completion_grace_ms(opts)
    cleanup_workspace? = Keyword.get(policy_opts, :cleanup_workspace?, false)
    stopped_skip_reason = Keyword.get(policy_opts, :stopped_skip_reason, "not_active")
    deferred_skip_reason = Keyword.get(policy_opts, :deferred_skip_reason, "completion_grace")

    case maybe_defer_completion(state, issue, now, grace_ms) do
      {:deferred, updated_state, observed_at} ->
        Events.issue_reconcile(opts, :info, :issue_reconcile_deferred, issue, updated_state, %{
          skip_reason: deferred_skip_reason,
          completion_state: stopped_skip_reason,
          grace_started_at: observed_at,
          grace_window_ms: grace_ms
        })

        updated_state

      :terminate ->
        Events.issue_reconcile(opts, :info, :issue_reconcile_stopped, issue, state, %{
          skip_reason: stopped_skip_reason
        })

        Termination.terminate_running_issue(state, issue.id, cleanup_workspace?, opts)
    end
  end

  def reconcile(_issue, state, _opts, _policy_opts), do: state

  @spec last_activity_timestamp(map()) :: DateTime.t() | nil
  def last_activity_timestamp(running_entry) when is_map(running_entry) do
    Map.get(running_entry, :last_agent_timestamp) || Map.get(running_entry, :started_at)
  end

  def last_activity_timestamp(_running_entry), do: nil

  defp maybe_defer_completion(state, %Issue{id: issue_id} = issue, now, grace_ms)
       when is_map(state) and is_binary(issue_id) and is_struct(now, DateTime) and
              is_integer(grace_ms) do
    case Map.get(StateView.running_entries(state), issue_id) do
      %{issue: _} = running_entry ->
        maybe_defer_running_entry(state, issue, issue_id, running_entry, now, grace_ms)

      _other ->
        :terminate
    end
  end

  defp maybe_defer_completion(_state, _issue, _now, _grace_ms), do: :terminate

  defp maybe_defer_running_entry(state, issue, issue_id, running_entry, now, grace_ms) do
    case Map.fetch(running_entry, @observed_at_key) do
      {:ok, %DateTime{} = observed_at} ->
        if grace_active?(observed_at, now, grace_ms) do
          defer_with_observed_at(state, issue, issue_id, running_entry, observed_at)
        else
          :terminate
        end

      _other ->
        if recent_agent_activity?(running_entry, now, grace_ms) do
          defer_with_observed_at(state, issue, issue_id, running_entry, now)
        else
          :terminate
        end
    end
  end

  defp defer_with_observed_at(state, issue, issue_id, running_entry, observed_at) do
    updated_entry =
      running_entry
      |> Map.put(:issue, issue)
      |> Map.put(@observed_at_key, observed_at)

    updated_state = StateView.put_running(state, Map.put(StateView.running_entries(state), issue_id, updated_entry))
    {:deferred, updated_state, observed_at}
  end

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

  defp completion_grace_ms(opts) do
    case Keyword.get(opts, :completion_grace_ms, 0) do
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
