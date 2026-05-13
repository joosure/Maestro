defmodule SymphonyElixir.Orchestrator.IssueDispatch do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Events
  alias SymphonyElixir.Orchestrator.Launch
  alias SymphonyElixir.Orchestrator.Retry
  alias SymphonyElixir.Orchestrator.Runtime
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Orchestrator.WorkerHosts
  alias SymphonyElixir.Tracker

  @spec choose_issues([Issue.t()], State.t()) :: State.t()
  def choose_issues(issues, %State{} = state) when is_list(issues) do
    dispatch_context = Runtime.dispatch_context()

    issues
    |> Dispatch.sort_issues_for_dispatch()
    |> Enum.reduce(state, fn issue, state_acc ->
      case Dispatch.dispatch_skip_reason(issue, Runtime.dispatch_runtime(state_acc), dispatch_context) do
        nil ->
          Events.emit_issue_dispatch(:info, :issue_dispatch_selected, issue, state_acc)
          dispatch_issue(state_acc, issue)

        skip_reason ->
          Events.emit_issue_dispatch(
            :info,
            :issue_dispatch_skipped,
            issue,
            state_acc,
            %{skip_reason: Atom.to_string(skip_reason)}
          )

          state_acc
      end
    end)
  end

  @spec dispatch_issue(State.t(), Issue.t()) :: State.t()
  def dispatch_issue(%State{} = state, %Issue{} = issue), do: dispatch_issue(state, issue, nil, nil)

  @spec dispatch_issue(State.t(), Issue.t(), pos_integer() | nil, String.t() | nil) :: State.t()
  def dispatch_issue(%State{} = state, %Issue{} = issue, attempt, preferred_worker_host) do
    dispatch_context = Runtime.dispatch_context()

    case Dispatch.revalidate_issue_for_dispatch(
           issue,
           &Tracker.fetch_issue_states_by_ids/1,
           dispatch_context
         ) do
      {:ok, %Issue{} = refreshed_issue} ->
        prepare_and_dispatch(state, refreshed_issue, attempt, preferred_worker_host, dispatch_context)

      {:skip, :missing} ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          issue,
          state,
          %{attempt: attempt, skip_reason: "refresh_missing"}
        )

        state

      {:skip, %Issue{} = refreshed_issue} ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          refreshed_issue,
          state,
          %{attempt: attempt, skip_reason: "refresh_not_dispatchable"}
        )

        state

      {:error, reason} ->
        Events.emit_issue_dispatch(
          :warning,
          :issue_dispatch_skipped,
          issue,
          state,
          %{attempt: attempt, skip_reason: "refresh_failed", error: inspect(reason)}
        )

        state
    end
  end

  defp prepare_and_dispatch(state, refreshed_issue, attempt, preferred_worker_host, dispatch_context) do
    case Dispatch.prepare_issue_for_dispatch(
           refreshed_issue,
           &Tracker.fetch_issue_states_by_ids/1,
           &Tracker.update_issue_state/2,
           dispatch_context,
           emit_route_transition: &Events.emit_route_transition/7
         ) do
      {:ok, %Issue{} = prepared_issue} ->
        do_dispatch_issue(state, prepared_issue, attempt, preferred_worker_host)

      {:skip, :missing} ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          refreshed_issue,
          state,
          %{attempt: attempt, skip_reason: "route_preparation_missing"}
        )

        state

      {:skip, %Issue{} = prepared_issue} ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          prepared_issue,
          state,
          %{attempt: attempt, skip_reason: "route_preparation_skipped"}
        )

        state

      {:error, reason} ->
        Events.emit_issue_dispatch(
          :warning,
          :issue_dispatch_skipped,
          refreshed_issue,
          state,
          %{attempt: attempt, skip_reason: "route_preparation_failed", error: inspect(reason)}
        )

        state
    end
  end

  defp do_dispatch_issue(%State{} = state, issue, attempt, preferred_worker_host) do
    recipient = self()

    case WorkerHosts.select_host(state, preferred_worker_host) do
      :no_worker_capacity ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          issue,
          state,
          %{attempt: attempt, skip_reason: "no_worker_capacity"}
        )

        state

      worker_host ->
        Launch.spawn_issue(
          state,
          issue,
          attempt,
          recipient,
          worker_host,
          emit_issue_dispatch: &Events.emit_issue_dispatch/5,
          schedule_retry: fn state, issue, next_attempt, metadata ->
            Retry.schedule(state, issue.id, next_attempt, metadata, emit_event: &Events.emit/5)
          end
        )
    end
  end
end
