defmodule SymphonyElixir.ChangeProposalReconciliation.Transition do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.{Contract, Events, RouteContext, TrackerCallOptions}
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.{Decision, Facts}
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef

  @spec apply(map(), Issue.t(), map(), RouteContext.t(), RouteFacts.t(), Facts.t(), Decision.t(), keyword()) ::
          map()
  def apply(
        settings,
        %Issue{} = issue,
        state,
        context,
        %RouteFacts{} = route_facts,
        %Facts{} = facts,
        %Decision{action: :move_to_route} = decision,
        opts
      )
      when is_map(settings) and is_map(state) and is_map(context) and is_list(opts) do
    transition_issue(settings, issue, state, context, route_facts, facts, decision, opts)
  end

  def apply(_settings, _issue, state, _context, _route_facts, _facts, _decision, _opts), do: state

  defp transition_issue(settings, issue, state, context, route_facts, facts, decision, opts) do
    target_route_ref = decision.target_route_ref
    target_state = RoutePolicy.raw_state_for_route_key(context.raw_state_by_route_key, target_route_ref.route_key)

    cond do
      is_nil(target_state) ->
        Events.transition(settings, :warning, Contract.event(:transition_failed), issue, state, route_facts, facts, decision, %{
          error: inspect({:missing_raw_state_for_route_key, target_route_ref})
        })

        state

      route_facts.route_key == target_route_ref.route_key ->
        Events.transition(settings, :info, Contract.event(:transition_skipped), issue, state, route_facts, facts, decision, %{
          skip_reason: :already_in_target_route,
          target_state: target_state
        })

        state

      dry_run?(opts) ->
        Events.transition(settings, :info, Contract.event(:transition_skipped), issue, state, route_facts, facts, decision, %{
          skip_reason: :dry_run,
          target_state: target_state
        })

        state

      true ->
        confirm_and_update_issue(settings, issue, state, route_facts, facts, decision, target_route_ref, target_state, opts)
    end
  end

  defp confirm_and_update_issue(settings, issue, state, route_facts, facts, decision, target_route_ref, target_state, opts) do
    Events.transition(settings, :info, Contract.event(:transition_attempted), issue, state, route_facts, facts, decision, %{
      target_state: target_state
    })

    with {:ok, %Issue{} = refreshed_issue} <- fetch_single_issue(issue.id, opts),
         {:ok, refreshed_route_facts} <-
           confirm_current_source_route(settings, refreshed_issue, route_facts.route_key),
         :ok <- update_issue_state(issue.id, target_state, route_facts.raw_state, opts),
         {:ok, %Issue{} = confirmed_issue} <- fetch_single_issue(issue.id, opts),
         :ok <- confirm_target_route(settings, confirmed_issue, target_route_ref) do
      Events.transition(
        settings,
        :info,
        Contract.event(:transition_succeeded),
        confirmed_issue,
        state,
        refreshed_route_facts,
        facts,
        decision,
        %{
          previous_state: issue.state,
          target_state: target_state
        }
      )

      state
    else
      {:skip, reason} ->
        Events.transition(settings, :info, Contract.event(:transition_skipped), issue, state, route_facts, facts, decision, %{
          skip_reason: reason,
          target_state: target_state
        })

        state

      {:error, reason} ->
        Events.transition(settings, :warning, Contract.event(:transition_failed), issue, state, route_facts, facts, decision, %{
          error: inspect(reason),
          target_state: target_state
        })

        state
    end
  end

  defp confirm_current_source_route(settings, %Issue{} = issue, expected_route) do
    case RouteContext.route_facts(issue, RouteContext.for_issue(settings, issue)) do
      %RouteFacts{route_key: ^expected_route} = route_facts -> {:ok, route_facts}
      %RouteFacts{} -> {:skip, :source_route_changed}
      nil -> {:skip, :route_unresolved}
    end
  end

  defp confirm_target_route(settings, %Issue{} = issue, %RouteRef{} = expected_route_ref) do
    route_context = RouteContext.for_issue(settings, issue)

    case RouteContext.route_facts(issue, route_context) do
      %RouteFacts{route_key: route_key} when route_key == expected_route_ref.route_key ->
        :ok

      %RouteFacts{} = route_facts ->
        {:error, {:target_route_unconfirmed, RouteRef.new!(route_context.profile_context, route_facts.route_key), expected_route_ref}}

      nil ->
        {:error, :target_route_unresolved}
    end
  end

  defp fetch_single_issue(issue_id, opts) when is_binary(issue_id) do
    case fetch_issue_states_by_ids([issue_id], opts) do
      {:ok, [%Issue{} = issue | _rest]} -> {:ok, issue}
      {:ok, []} -> {:skip, :issue_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_single_issue(_issue_id, _opts), do: {:skip, :missing_issue_id}

  defp fetch_issue_states_by_ids(issue_ids, opts) do
    Keyword.get(opts, :fetch_issue_states_by_ids_fn, &Tracker.fetch_issue_states_by_ids/2).(
      issue_ids,
      TrackerCallOptions.fetch(opts)
    )
  end

  defp update_issue_state(issue_id, target_state, expected_current_state, opts) do
    update_opts = Keyword.put(TrackerCallOptions.write(opts), :expected_current_state, expected_current_state)

    Keyword.get(opts, :update_issue_state_fn, &Tracker.update_issue_state/3).(issue_id, target_state, update_opts)
  end

  defp dry_run?(opts) when is_list(opts) do
    Keyword.get(opts, :dry_run?, false) || Keyword.get(opts, :dry_run, false)
  end
end
