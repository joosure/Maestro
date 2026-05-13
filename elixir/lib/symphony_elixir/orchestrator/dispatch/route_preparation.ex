defmodule SymphonyElixir.Orchestrator.Dispatch.RoutePreparation do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch.{Context, Eligibility}
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy, as: WorkflowRoutePolicy

  @spec prepare(
          Issue.t(),
          ([String.t()] -> term()),
          (String.t(), term() -> term()),
          Context.t(),
          keyword()
        ) :: {:ok, Issue.t()} | {:skip, Issue.t() | :missing} | {:error, term()}
  def prepare(issue, issue_fetcher, state_updater, context, opts \\ [])

  def prepare(%Issue{} = issue, issue_fetcher, state_updater, context, opts)
      when is_function(issue_fetcher, 1) and is_function(state_updater, 2) and is_map(context) do
    case route_preparation_action(issue) do
      {:dispatch, _route_key, _policy, _raw_state_by_route_key} ->
        {:ok, issue}

      {:wait, _route_key, _policy, _raw_state_by_route_key} ->
        {:skip, issue}

      {:stop, _route_key, _policy, _raw_state_by_route_key} ->
        {:skip, issue}

      {:transition, route_key, policy, raw_state_by_route_key, dispatch_after_transition?} ->
        prepare_route_transition(
          issue,
          route_key,
          policy,
          raw_state_by_route_key,
          dispatch_after_transition?,
          issue_fetcher,
          state_updater,
          context,
          Keyword.get(opts, :emit_route_transition)
        )
    end
  end

  def prepare(issue, _issue_fetcher, _state_updater, _context, _opts), do: {:ok, issue}

  defp prepare_route_transition(
         %Issue{} = issue,
         route_key,
         policy,
         raw_state_by_route_key,
         dispatch_after_transition?,
         issue_fetcher,
         state_updater,
         context,
         route_transition_emitter
       ) do
    transition_target = Map.get(policy, :transition_target)
    target_state = WorkflowRoutePolicy.raw_state_for_route_key(raw_state_by_route_key, transition_target)

    emit_route_transition(
      route_transition_emitter,
      :info,
      :route_preparation_started,
      issue,
      route_key,
      transition_target,
      target_state,
      %{policy_action: Map.get(policy, :action)}
    )

    emit_route_transition(
      route_transition_emitter,
      :info,
      :route_transition_attempted,
      issue,
      route_key,
      transition_target,
      target_state
    )

    with :ok <-
           normalize_state_update_result(
             state_updater.(issue.id, target_state),
             route_key,
             transition_target,
             target_state
           ),
         {:ok, refreshed_issue} <- refresh_issue_after_route_transition(issue, issue_fetcher),
         :ok <- confirm_route_transition(refreshed_issue, raw_state_by_route_key, transition_target) do
      emit_route_transition(
        route_transition_emitter,
        :info,
        :route_transition_succeeded,
        refreshed_issue,
        route_key,
        transition_target,
        target_state,
        %{previous_state: issue.state}
      )

      if dispatch_after_transition? and Eligibility.retry_candidate_issue?(refreshed_issue, context) do
        {:ok, refreshed_issue}
      else
        {:skip, refreshed_issue}
      end
    else
      {:skip, _issue_or_marker} = skip ->
        emit_route_transition(
          route_transition_emitter,
          :warning,
          :route_transition_unconfirmed,
          issue,
          route_key,
          transition_target,
          target_state,
          %{previous_state: issue.state, error: inspect(skip)}
        )

        skip

      {:error, {:route_transition_unconfirmed, current_state, _target_route_key} = reason} ->
        emit_route_transition(
          route_transition_emitter,
          :warning,
          :route_transition_unconfirmed,
          issue,
          route_key,
          transition_target,
          target_state,
          %{previous_state: issue.state, current_state: current_state, error: inspect(reason)}
        )

        {:error, reason}

      {:error, reason} ->
        emit_route_transition(
          route_transition_emitter,
          :warning,
          :route_transition_failed,
          issue,
          route_key,
          transition_target,
          target_state,
          %{previous_state: issue.state, error: inspect(reason)}
        )

        {:error, reason}
    end
  end

  defp route_preparation_action(%Issue{} = issue) do
    raw_state_by_route_key = IssueContext.raw_state_by_route_key(issue, nil)

    cond do
      not is_map(raw_state_by_route_key) or map_size(raw_state_by_route_key) == 0 ->
        {:dispatch, nil, %{}, %{}}

      true ->
        route_facts = IssueContext.route_facts(issue)
        route_key = if is_nil(route_facts), do: nil, else: route_facts.route_key
        policy = if is_nil(route_facts), do: %{action: :dispatch}, else: RouteFacts.policy_map(route_facts)

        case Map.get(policy, :action) do
          :wait -> {:wait, route_key, policy, raw_state_by_route_key}
          :stop -> {:stop, route_key, policy, raw_state_by_route_key}
          :transition -> {:transition, route_key, policy, raw_state_by_route_key, false}
          :transition_then_dispatch -> {:transition, route_key, policy, raw_state_by_route_key, true}
          _other -> {:dispatch, route_key, policy, raw_state_by_route_key}
        end
    end
  end

  defp refresh_issue_after_route_transition(%Issue{id: issue_id}, issue_fetcher)
       when is_binary(issue_id) and is_function(issue_fetcher, 1) do
    case issue_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        {:ok, refreshed_issue}

      {:ok, []} ->
        {:skip, :missing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp refresh_issue_after_route_transition(_issue, _issue_fetcher), do: {:skip, :missing}

  defp confirm_route_transition(%Issue{} = issue, source_raw_state_by_route_key, target_route_key)
       when is_atom(target_route_key) do
    raw_state_by_route_key = IssueContext.raw_state_by_route_key(issue, source_raw_state_by_route_key)
    profile_module = IssueContext.profile_context(issue).module

    if WorkflowRoutePolicy.route_key_for_raw_state(issue.state, raw_state_by_route_key, profile_module) == target_route_key do
      :ok
    else
      {:error, {:route_transition_unconfirmed, issue.state, target_route_key}}
    end
  end

  defp normalize_state_update_result(:ok, _route_key, _transition_target, _target_state), do: :ok

  defp normalize_state_update_result({:error, reason}, route_key, transition_target, target_state) do
    {:error, {:route_transition_failed, route_key, transition_target, target_state, reason}}
  end

  defp normalize_state_update_result(other, route_key, transition_target, target_state) do
    {:error, {:route_transition_failed, route_key, transition_target, target_state, other}}
  end

  defp emit_route_transition(
         route_transition_emitter,
         level,
         event,
         issue,
         route_key,
         transition_target,
         target_state,
         extra_fields \\ %{}
       )

  defp emit_route_transition(
         route_transition_emitter,
         level,
         event,
         %Issue{} = issue,
         route_key,
         transition_target,
         target_state,
         extra_fields
       )
       when is_function(route_transition_emitter, 7) and is_map(extra_fields) do
    route_transition_emitter.(
      level,
      event,
      issue,
      route_key,
      transition_target,
      target_state,
      extra_fields
    )
  end

  defp emit_route_transition(
         _route_transition_emitter,
         _level,
         _event,
         _issue,
         _route_key,
         _transition_target,
         _target_state,
         _extra_fields
       ),
       do: :ok
end
