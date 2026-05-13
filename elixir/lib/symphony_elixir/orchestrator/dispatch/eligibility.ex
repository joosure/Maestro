defmodule SymphonyElixir.Orchestrator.Dispatch.Eligibility do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch.{Context, RuntimeView}
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @type context :: Context.t()
  @type runtime :: RuntimeView.t()

  @spec should_dispatch_issue?(Issue.t(), runtime(), context()) :: boolean()
  def should_dispatch_issue?(%Issue{} = issue, runtime, context) when is_map(runtime) and is_map(context) do
    is_nil(dispatch_skip_reason(issue, runtime, context))
  end

  def should_dispatch_issue?(_issue, _runtime, _context), do: false

  @spec dispatch_skip_reason(Issue.t(), runtime(), context()) :: atom() | nil
  def dispatch_skip_reason(%Issue{} = issue, runtime, context) when is_map(runtime) and is_map(context) do
    candidate? = candidate_issue?(issue, context)
    terminal? = terminal_issue_state?(issue, issue.state, context)
    running = RuntimeView.running(runtime)
    claimed = RuntimeView.claimed(runtime)

    cond do
      not candidate? and terminal? ->
        :terminal

      not candidate? and not issue_routable_to_worker?(issue) ->
        :not_routed

      not candidate? ->
        :not_active

      issue_blocked_by_non_terminal_for_dispatch?(issue, context) ->
        :blocked

      Enum.member?(claimed, issue.id) ->
        :claimed

      Map.has_key?(running, issue.id) ->
        :already_running

      RuntimeView.orchestrator_slots(runtime) <= 0 ->
        :no_orchestrator_slots

      not state_slots_available?(issue, running, context) ->
        :state_limit_reached

      not RuntimeView.worker_slots_available?(runtime) ->
        :no_worker_capacity

      true ->
        nil
    end
  end

  def dispatch_skip_reason(_issue, _runtime, _context), do: :invalid_issue

  @spec issue_routable_to_worker?(Issue.t()) :: boolean()
  def issue_routable_to_worker?(%Issue{assigned_to_worker: assigned_to_worker})
      when is_boolean(assigned_to_worker),
      do: assigned_to_worker

  def issue_routable_to_worker?(_issue), do: true

  @spec terminal_issue_state?(Issue.t(), term(), context()) :: boolean()
  def terminal_issue_state?(%Issue{} = issue, state_name, %{terminal_state_names: terminal_state_names})
      when is_binary(state_name) and is_list(terminal_state_names) do
    normalized_state_name = WorkflowLifecycle.normalize_tracker_state(state_name)

    issue
    |> IssueContext.terminal_states(terminal_state_names)
    |> Context.normalized_state_names()
    |> Enum.member?(normalized_state_name)
  end

  def terminal_issue_state?(_issue, _state_name, _context), do: false

  @spec active_issue_state?(Issue.t(), term(), context()) :: boolean()
  def active_issue_state?(%Issue{} = issue, state_name, %{active_state_names: active_state_names})
      when is_binary(state_name) and is_list(active_state_names) do
    normalized_state_name = WorkflowLifecycle.normalize_tracker_state(state_name)

    issue
    |> IssueContext.active_states(active_state_names)
    |> Context.normalized_state_names()
    |> Enum.member?(normalized_state_name)
  end

  def active_issue_state?(_issue, _state_name, _context), do: false

  @spec retry_candidate_issue?(Issue.t(), context()) :: boolean()
  def retry_candidate_issue?(%Issue{} = issue, context) when is_map(context) do
    candidate_issue?(issue, context) and
      not issue_blocked_by_non_terminal_for_dispatch?(issue, context)
  end

  def retry_candidate_issue?(_issue, _context), do: false

  @spec dispatch_slots_available?(Issue.t(), runtime(), context()) :: boolean()
  def dispatch_slots_available?(%Issue{} = issue, runtime, context)
      when is_map(runtime) and is_map(context) do
    RuntimeView.orchestrator_slots(runtime) > 0 and
      state_slots_available?(issue, RuntimeView.running(runtime), context)
  end

  def dispatch_slots_available?(_issue, _runtime, _context), do: false

  defp candidate_issue?(
         %Issue{
           id: id,
           identifier: identifier,
           title: title,
           state: state_name
         } = issue,
         context
       )
       when is_binary(id) and is_binary(identifier) and is_binary(title) and is_binary(state_name) do
    issue_routable_to_worker?(issue) and
      active_issue_state?(issue, state_name, context) and
      not terminal_issue_state?(issue, state_name, context)
  end

  defp candidate_issue?(_issue, _context), do: false

  defp issue_blocked_by_non_terminal_for_dispatch?(
         %Issue{lifecycle_phase: lifecycle_phase, state: state_name, blocked_by: blockers} = issue,
         context
       )
       when is_list(blockers) do
    blocker_gate_applies?(resolved_lifecycle_phase(issue, lifecycle_phase, state_name, context)) and
      Enum.any?(blockers, fn
        %{lifecycle_phase: blocker_phase} when is_binary(blocker_phase) ->
          not WorkflowLifecycle.terminal_phase?(blocker_phase)

        %{state: blocker_state} when is_binary(blocker_state) ->
          case resolved_lifecycle_phase(issue, nil, blocker_state, context) do
            nil -> not terminal_issue_state?(issue, blocker_state, context)
            blocker_phase -> not WorkflowLifecycle.terminal_phase?(blocker_phase)
          end

        _other ->
          true
      end)
  end

  defp issue_blocked_by_non_terminal_for_dispatch?(_issue, _context), do: false

  defp blocker_gate_applies?(lifecycle_phase) when is_binary(lifecycle_phase),
    do: WorkflowLifecycle.dispatch_blocker_phase?(lifecycle_phase)

  defp blocker_gate_applies?(_lifecycle_phase), do: false

  defp resolved_lifecycle_phase(_issue, lifecycle_phase, _state_name, _context)
       when is_binary(lifecycle_phase),
       do: lifecycle_phase

  defp resolved_lifecycle_phase(%Issue{} = issue, _lifecycle_phase, state_name, context)
       when is_binary(state_name) and is_map(context) do
    WorkflowLifecycle.phase_for_state(
      state_name,
      IssueContext.state_phase_map(issue, Context.state_phase_map(context))
    )
  end

  defp resolved_lifecycle_phase(_issue, _lifecycle_phase, _state_name, _context), do: nil

  defp state_slots_available?(%Issue{state: issue_state}, running, context)
       when is_map(running) and is_map(context) do
    limit = max_concurrent_agents_for_state(context, issue_state)
    used = running_issue_count_for_state(running, issue_state)
    limit > used
  end

  defp state_slots_available?(_issue, _running, _context), do: false

  defp running_issue_count_for_state(running, issue_state) when is_map(running) do
    normalized_state = WorkflowLifecycle.normalize_tracker_state(issue_state)

    Enum.count(running, fn
      {_id, %{issue: %Issue{state: state_name}}} ->
        WorkflowLifecycle.normalize_tracker_state(state_name) == normalized_state

      _other ->
        false
    end)
  end

  defp max_concurrent_agents_for_state(context, issue_state) do
    case Map.get(context, :max_concurrent_agents_for_state) do
      fun when is_function(fun, 1) ->
        case fun.(issue_state) do
          limit when is_integer(limit) and limit > 0 -> limit
          _other -> 0
        end

      _other ->
        0
    end
  end
end
