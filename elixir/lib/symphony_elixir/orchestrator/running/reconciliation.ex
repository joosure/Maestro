defmodule SymphonyElixir.Orchestrator.Running.Reconciliation do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Running.{Events, InactiveGrace, StateView, Termination}

  @spec reconcile_issue_states(list(), map(), map(), keyword()) :: map()
  def reconcile_issue_states(issues, state, dispatch_context, opts)
      when is_list(issues) and is_map(state) and is_map(dispatch_context) do
    requested_issue_ids = Map.keys(StateView.running_entries(state))

    issues
    |> do_reconcile_issue_states(state, dispatch_context, opts)
    |> reconcile_missing_issue_ids(requested_issue_ids, issues, opts)
  end

  def reconcile_issue_states(_issues, state, _dispatch_context, _opts), do: state

  defp do_reconcile_issue_states([], state, _dispatch_context, _opts), do: state

  defp do_reconcile_issue_states([issue | rest], state, dispatch_context, opts) do
    do_reconcile_issue_states(
      rest,
      reconcile_issue_state(issue, state, dispatch_context, opts),
      dispatch_context,
      opts
    )
  end

  defp reconcile_issue_state(%Issue{} = issue, state, dispatch_context, opts) do
    cond do
      Dispatch.terminal_issue_state?(issue, issue.state, dispatch_context) ->
        Events.issue_reconcile(opts, :info, :issue_reconcile_stopped, issue, state, %{
          skip_reason: "terminal"
        })

        Termination.terminate_running_issue(state, issue.id, true, opts)

      not Dispatch.issue_routable_to_worker?(issue) ->
        Events.issue_reconcile(opts, :info, :issue_reconcile_stopped, issue, state, %{
          skip_reason: "not_routed"
        })

        Termination.terminate_running_issue(state, issue.id, false, opts)

      Dispatch.active_issue_state?(issue, issue.state, dispatch_context) ->
        refresh_running_issue_state(state, issue)

      true ->
        InactiveGrace.reconcile(issue, state, opts)
    end
  end

  defp reconcile_issue_state(_issue, state, _dispatch_context, _opts), do: state

  defp reconcile_missing_issue_ids(state, requested_issue_ids, issues, opts)
       when is_list(requested_issue_ids) and is_list(issues) do
    visible_issue_ids =
      issues
      |> Enum.flat_map(fn
        %Issue{id: issue_id} when is_binary(issue_id) -> [issue_id]
        _other -> []
      end)
      |> MapSet.new()

    Enum.reduce(requested_issue_ids, state, fn issue_id, state_acc ->
      if MapSet.member?(visible_issue_ids, issue_id) do
        state_acc
      else
        log_missing_running_issue(state_acc, issue_id, opts)
        Termination.terminate_running_issue(state_acc, issue_id, false, opts)
      end
    end)
  end

  defp reconcile_missing_issue_ids(state, _requested_issue_ids, _issues, _opts), do: state

  defp log_missing_running_issue(state, issue_id, opts) when is_binary(issue_id) do
    case Map.get(StateView.running_entries(state), issue_id) do
      %{identifier: identifier} ->
        Events.emit(opts, :info, :issue_reconcile_stopped, nil, state, %{
          issue_id: issue_id,
          issue_identifier: identifier,
          skip_reason: "missing_visible"
        })

      _other ->
        Events.emit(opts, :info, :issue_reconcile_stopped, nil, state, %{
          issue_id: issue_id,
          skip_reason: "missing_visible"
        })
    end
  end

  defp log_missing_running_issue(_state, _issue_id, _opts), do: :ok

  defp refresh_running_issue_state(state, %Issue{} = issue) do
    case Map.get(StateView.running_entries(state), issue.id) do
      %{issue: _} = running_entry ->
        updated_entry =
          running_entry
          |> Map.put(:issue, issue)
          |> Map.delete(:non_active_observed_at)

        StateView.put_running(state, Map.put(StateView.running_entries(state), issue.id, updated_entry))

      _other ->
        state
    end
  end
end
