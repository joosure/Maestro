defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.{Contract, Decision, Events, Facts, RouteContext}
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition.{Clients, Diagnostics, Options}
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef

  @spec apply(map(), Issue.t(), map(), RouteContext.t(), RouteFacts.t(), Facts.t(), Decision.t(), term()) ::
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
      when is_map(settings) and is_map(state) and is_map(context) do
    case Options.normalize(opts) do
      {:ok, options} ->
        transition_issue(settings, issue, state, context, route_facts, facts, decision, options)

      {:error, reason} ->
        transition_failed(settings, issue, state, route_facts, facts, decision, reason)
    end
  end

  def apply(_settings, _issue, state, _context, _route_facts, _facts, _decision, _opts), do: state

  defp transition_issue(settings, issue, state, context, route_facts, facts, decision, %Options{} = options) do
    target_route_ref = decision.target_route_ref
    target_state = RoutePolicy.raw_state_for_route_key(context.raw_state_by_route_key, target_route_ref.route_key)

    cond do
      is_nil(target_state) ->
        transition_failed(settings, issue, state, route_facts, facts, decision, Diagnostics.missing_raw_state_for_route_key(target_route_ref))

      route_facts.route_key == target_route_ref.route_key ->
        Events.transition(settings, :info, Contract.event(:transition_skipped), issue, state, route_facts, facts, decision, %{
          Fields.skip_reason() => :already_in_target_route,
          Fields.target_state() => target_state
        })

        state

      options.dry_run? ->
        Events.transition(settings, :info, Contract.event(:transition_skipped), issue, state, route_facts, facts, decision, %{
          Fields.skip_reason() => :dry_run,
          Fields.target_state() => target_state
        })

        state

      true ->
        confirm_and_update_issue(settings, issue, state, route_facts, facts, decision, target_route_ref, target_state, options)
    end
  end

  defp confirm_and_update_issue(settings, issue, state, route_facts, facts, decision, target_route_ref, target_state, %Options{} = options) do
    Events.transition(settings, :info, Contract.event(:transition_attempted), issue, state, route_facts, facts, decision, %{
      Fields.target_state() => target_state
    })

    with {:ok, %Issue{} = refreshed_issue} <- fetch_single_issue(issue.id, options),
         {:ok, refreshed_route_facts} <-
           confirm_current_source_route(settings, refreshed_issue, route_facts.route_key),
         :ok <- Clients.update_issue_state(issue.id, target_state, route_facts.raw_state, options),
         {:ok, %Issue{} = confirmed_issue} <- fetch_single_issue(issue.id, options),
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
          Fields.previous_state() => issue.state,
          Fields.target_state() => target_state
        }
      )

      state
    else
      {:skip, reason} ->
        Events.transition(settings, :info, Contract.event(:transition_skipped), issue, state, route_facts, facts, decision, %{
          Fields.skip_reason() => reason,
          Fields.target_state() => target_state
        })

        state

      {:error, reason} ->
        transition_failed(settings, issue, state, route_facts, facts, decision, reason, target_state)
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
        {:error, Diagnostics.target_route_unconfirmed(route_facts.route_key, expected_route_ref)}

      nil ->
        {:error, :target_route_unresolved}
    end
  end

  defp fetch_single_issue(issue_id, %Options{} = options) when is_binary(issue_id) do
    case Clients.fetch_issue_states_by_ids([issue_id], options) do
      {:ok, [%Issue{} = issue | _rest]} -> {:ok, issue}
      {:ok, []} -> {:skip, :issue_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_single_issue(_issue_id, %Options{}), do: {:skip, :missing_issue_id}

  defp transition_failed(settings, issue, state, route_facts, facts, decision, reason, target_state \\ nil) do
    fields = %{Fields.error() => Diagnostics.error(reason)}
    fields = if is_binary(target_state), do: Map.put(fields, Fields.target_state(), target_state), else: fields

    Events.transition(settings, :warning, Contract.event(:transition_failed), issue, state, route_facts, facts, decision, fields)
    state
  end
end
