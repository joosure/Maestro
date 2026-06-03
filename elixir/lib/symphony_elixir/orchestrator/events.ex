defmodule SymphonyElixir.Orchestrator.Events do
  @moduledoc false

  alias SymphonyElixir.{Config, Issue}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.{IssueContext, RouteRef}

  @spec emit_route_transition(
          Logger.level(),
          atom(),
          Issue.t(),
          term(),
          term(),
          term(),
          map()
        ) :: map()
  def emit_route_transition(
        level,
        event,
        %Issue{} = issue,
        route_key,
        transition_target,
        target_state,
        extra_fields
      )
      when is_map(extra_fields) do
    profile_context = IssueContext.profile_context(issue)
    route_ref = RouteRef.new!(profile_context, route_key)
    target_route_ref = RouteRef.new!(profile_context, transition_target)

    ObservabilityLogger.emit(
      level,
      event,
      Map.merge(
        %{
          component: "orchestrator",
          issue_id: issue.id,
          issue_identifier: issue.identifier,
          tracker_kind: tracker_kind(),
          target_state: target_state,
          current_state: issue.state
        },
        route_ref
        |> RouteRef.event_fields()
        |> Map.merge(RouteRef.transition_target_event_fields(target_route_ref))
        |> Map.merge(extra_fields)
      )
    )
  end

  @spec emit_config_validation_failed(term()) :: map()
  def emit_config_validation_failed(reason) do
    ObservabilityLogger.emit(
      :error,
      :config_validation_failed,
      fields(nil, nil, %{error: inspect(reason)})
    )
  end

  @spec emit_tracker_candidate_fetch_failed(map(), term()) :: map()
  def emit_tracker_candidate_fetch_failed(state, reason) when is_map(state) do
    emit(:error, :tracker_candidate_fetch_failed, nil, state, %{
      error: inspect(reason),
      result_summary: "candidate_fetch_failed"
    })
  end

  @spec emit_issue_worker_finished(map(), String.t(), map(), term(), String.t(), String.t()) ::
          map()
  def emit_issue_worker_finished(state, issue_id, running_entry, reason, status, result_summary)
      when is_map(state) and is_binary(issue_id) and is_map(running_entry) and is_binary(status) and
             is_binary(result_summary) do
    issue = Map.get(running_entry, :issue)
    session_id = running_entry_session_id(running_entry)
    issue_identifier = Map.get(running_entry, :identifier) || issue_identifier(issue)

    extra_fields =
      %{
        issue_id: issue_id,
        issue_identifier: issue_identifier,
        run_id: Map.get(running_entry, :run_id),
        session_id: session_id,
        current_state: issue && issue.state,
        status: status,
        result_summary: result_summary,
        worker_host: Map.get(running_entry, :worker_host),
        workspace_path: Map.get(running_entry, :workspace_path),
        failure_class: Map.get(running_entry, :failure_class),
        message: "issue_worker_finished issue_id=#{issue_id} issue_identifier=#{issue_identifier} session_id=#{session_id} status=#{status} result=#{result_summary}"
      }
      |> maybe_put_error(reason)
      |> maybe_append_reason_to_message(reason)

    emit(
      if(reason == :normal, do: :info, else: :warning),
      :issue_worker_finished,
      issue,
      state,
      extra_fields
    )
  end

  @spec emit_issue_dispatch(Logger.level(), atom(), Issue.t(), map(), map()) :: map()
  def emit_issue_dispatch(level, event, %Issue{} = issue, state, extra_fields \\ %{})
      when is_map(extra_fields) do
    ObservabilityLogger.emit(
      level,
      event,
      fields(
        issue,
        state,
        Map.merge(
          %{
            current_state: issue.state
          },
          extra_fields
        )
      )
    )
  end

  @spec emit_poll_cycle(Logger.level(), atom(), map(), map()) :: map()
  def emit_poll_cycle(level, event, state, extra_fields \\ %{}) when is_map(state) and is_map(extra_fields) do
    ObservabilityLogger.emit(level, event, fields(nil, state, extra_fields))
  end

  @spec emit_issue_reconcile(Logger.level(), atom(), Issue.t(), map(), map()) :: map()
  def emit_issue_reconcile(level, event, %Issue{} = issue, state, extra_fields)
      when is_map(state) and is_map(extra_fields) do
    emit(
      level,
      event,
      issue,
      state,
      Map.merge(
        %{
          current_state: issue.state
        },
        extra_fields
      )
    )
  end

  @spec emit_reconcile_refresh_failed(map(), term()) :: map()
  def emit_reconcile_refresh_failed(state, reason) when is_map(state) do
    emit(:warning, :issue_reconcile_refresh_failed, nil, state, %{error: inspect(reason)})
  end

  @spec emit(Logger.level(), atom(), Issue.t() | nil, map() | nil, map()) :: map()
  def emit(level, event, issue, state, extra_fields) when is_map(extra_fields) do
    ObservabilityLogger.emit(level, event, fields(issue, state, extra_fields))
  end

  @spec available_slots(map()) :: non_neg_integer()
  def available_slots(state) when is_map(state) do
    max(
      (Map.get(state, :max_concurrent_agents) || Config.settings!().agent.execution.max_concurrent_agents) -
        map_size(running_entries(state)),
      0
    )
  end

  def available_slots(_state), do: 0

  defp fields(issue, state, extra_fields) do
    fields =
      %{
        component: "orchestrator",
        tracker_kind: tracker_kind(),
        issue_id: issue_id(issue),
        issue_identifier: issue_identifier(issue),
        running_count: running_count(state),
        claimed_count: claimed_count(state),
        available_slots: available_slots_for_event(state),
        max_concurrent_agents: max_concurrent_agents_for_event(state)
      }
      |> Map.merge(extra_fields)

    case Map.get(fields, :run_id) || Map.get(fields, "run_id") do
      run_id when is_binary(run_id) -> Map.put_new(fields, :correlation_id, run_id)
      _ -> fields
    end
  end

  defp tracker_kind, do: Tracker.current_kind()

  defp running_entry_session_id(%{session_id: session_id}) when is_binary(session_id),
    do: session_id

  defp running_entry_session_id(_running_entry), do: "n/a"

  defp issue_id(%Issue{id: issue_id}), do: issue_id
  defp issue_id(_issue), do: nil

  defp issue_identifier(%Issue{identifier: identifier}), do: identifier
  defp issue_identifier(_issue), do: nil

  defp maybe_put_error(fields, :normal), do: fields
  defp maybe_put_error(fields, reason), do: Map.put(fields, :error, inspect(reason))

  defp maybe_append_reason_to_message(%{message: _message} = fields, :normal), do: fields

  defp maybe_append_reason_to_message(%{message: message} = fields, reason) do
    %{fields | message: "#{message} reason=#{inspect(reason)}"}
  end

  defp running_count(%{running: running}) when is_map(running), do: map_size(running)
  defp running_count(_state), do: nil

  defp claimed_count(%{claimed: claimed}) when is_struct(claimed, MapSet), do: MapSet.size(claimed)
  defp claimed_count(_state), do: nil

  defp available_slots_for_event(state) when is_map(state), do: available_slots(state)
  defp available_slots_for_event(_state), do: nil

  defp max_concurrent_agents_for_event(%{max_concurrent_agents: max}) when is_integer(max), do: max
  defp max_concurrent_agents_for_event(_state), do: nil

  defp running_entries(%{running: running}) when is_map(running), do: running
  defp running_entries(_state), do: %{}
end
