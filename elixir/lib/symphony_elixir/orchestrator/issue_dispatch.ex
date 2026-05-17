defmodule SymphonyElixir.Orchestrator.IssueDispatch do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Dispatch.Context, as: DispatchContext
  alias SymphonyElixir.Orchestrator.Events
  alias SymphonyElixir.Orchestrator.Launch
  alias SymphonyElixir.Orchestrator.Retry
  alias SymphonyElixir.Orchestrator.Runtime
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Orchestrator.WorkerHosts
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.Readiness
  alias SymphonyElixir.Workflow.ReadinessContract

  @spec choose_issues([Issue.t()], State.t()) :: State.t()
  def choose_issues(issues, %State{} = state) when is_list(issues) do
    dispatch_context = Runtime.dispatch_context()

    issues
    |> Dispatch.sort_issues_for_dispatch()
    |> Enum.reduce(state, fn issue, state_acc ->
      case Dispatch.dispatch_skip_reason(issue, Runtime.dispatch_runtime(state_acc), dispatch_context) do
        nil ->
          Events.emit_issue_dispatch(
            :info,
            :issue_dispatch_selected,
            issue,
            state_acc,
            workflow_event_fields(issue, dispatch_context)
          )

          dispatch_issue(state_acc, issue)

        skip_reason ->
          Events.emit_issue_dispatch(
            :info,
            :issue_dispatch_skipped,
            issue,
            state_acc,
            Map.merge(
              workflow_event_fields(issue, dispatch_context),
              %{skip_reason: Atom.to_string(skip_reason)}
            )
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
          Map.merge(
            workflow_event_fields(issue, dispatch_context),
            %{attempt: attempt, skip_reason: "refresh_missing"}
          )
        )

        state

      {:skip, %Issue{} = refreshed_issue} ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          refreshed_issue,
          state,
          Map.merge(
            workflow_event_fields(refreshed_issue, dispatch_context),
            %{attempt: attempt, skip_reason: "refresh_not_dispatchable"}
          )
        )

        state

      {:error, reason} ->
        Events.emit_issue_dispatch(
          :warning,
          :issue_dispatch_skipped,
          issue,
          state,
          Map.merge(
            workflow_event_fields(issue, dispatch_context),
            %{attempt: attempt, skip_reason: "refresh_failed", error: inspect(reason)}
          )
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
        do_dispatch_issue(state, prepared_issue, attempt, preferred_worker_host, dispatch_context)

      {:skip, :missing} ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          refreshed_issue,
          state,
          Map.merge(
            workflow_event_fields(refreshed_issue, dispatch_context),
            %{attempt: attempt, skip_reason: "route_preparation_missing"}
          )
        )

        state

      {:skip, %Issue{} = prepared_issue} ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          prepared_issue,
          state,
          Map.merge(
            workflow_event_fields(prepared_issue, dispatch_context),
            %{attempt: attempt, skip_reason: "route_preparation_skipped"}
          )
        )

        state

      {:error, reason} ->
        Events.emit_issue_dispatch(
          :warning,
          :issue_dispatch_skipped,
          refreshed_issue,
          state,
          Map.merge(
            workflow_event_fields(refreshed_issue, dispatch_context),
            %{attempt: attempt, skip_reason: "route_preparation_failed", error: inspect(reason)}
          )
        )

        state
    end
  end

  defp do_dispatch_issue(%State{} = state, issue, attempt, preferred_worker_host, dispatch_context) do
    recipient = self()

    case WorkerHosts.select_host(state, preferred_worker_host) do
      :no_worker_capacity ->
        Events.emit_issue_dispatch(
          :info,
          :issue_dispatch_skipped,
          issue,
          state,
          Map.merge(
            workflow_event_fields(issue, dispatch_context),
            %{attempt: attempt, skip_reason: "no_worker_capacity"}
          )
        )

        state

      worker_host ->
        Launch.spawn_issue(
          state,
          issue,
          attempt,
          recipient,
          worker_host,
          emit_issue_dispatch: fn level, event, issue, state, extra_fields ->
            Events.emit_issue_dispatch(
              level,
              event,
              issue,
              state,
              Map.merge(workflow_event_fields(issue, dispatch_context), extra_fields)
            )
          end,
          schedule_retry: fn state, issue, next_attempt, metadata ->
            Retry.schedule(state, issue.id, next_attempt, metadata, emit_event: &Events.emit/5)
          end
        )
    end
  end

  defp workflow_event_fields(%Issue{} = issue, dispatch_context) when is_map(dispatch_context) do
    facts =
      Readiness.facts(issue,
        settings: DispatchContext.workflow_settings(dispatch_context),
        available_capabilities: DispatchContext.available_capabilities(dispatch_context)
      )

    profile = Map.get(facts, ReadinessContract.profile_key(), %{})
    route = Map.get(facts, ReadinessContract.route_key(), %{})
    gate = Map.get(facts, ReadinessContract.gate_key(), %{})
    capabilities = Map.get(facts, "capabilities", %{})

    %{
      workflow_profile: Map.get(profile, "kind"),
      workflow_profile_version: Map.get(profile, "version"),
      workflow_route_key: Map.get(route, ReadinessContract.key_key()),
      workflow_route_action: Map.get(route, "action"),
      workflow_gate_status: Map.get(gate, ReadinessContract.status_key()),
      workflow_gate: ReadinessContract.gate(gate),
      workflow_gate_reason: Map.get(gate, ReadinessContract.reason_key()),
      workflow_missing_capabilities: Map.get(capabilities, "missing", [])
    }
  end

  defp workflow_event_fields(_issue, _dispatch_context), do: %{}
end
