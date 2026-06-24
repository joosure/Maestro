defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.{
    BaseFields,
    ChangeProposalFields,
    Diagnostics,
    Emitter,
    Fields,
    RouteFields
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.{Config, Decision, Facts}
  alias SymphonyElixir.Workflow.RouteFacts

  @spec config_invalid(map(), map(), term()) :: map()
  def config_invalid(settings, state, reason) when is_map(settings) and is_map(state) do
    emit(settings, :warning, Contract.event(:config_invalid), nil, state, %{
      Fields.error() => Diagnostics.error(reason)
    })
  end

  @spec reconciliation_started(map(), map(), Config.t(), [String.t()]) :: map()
  def reconciliation_started(settings, state, %Config{} = config, source_raw_states)
      when is_map(settings) and is_map(state) and is_list(source_raw_states) do
    emit(settings, :info, Contract.event(:reconciliation_started), nil, state, %{
      Fields.source_route_refs() => RouteFields.route_ref_maps(config.source_routes),
      Fields.source_states() => source_raw_states
    })
  end

  @spec reconciliation_completed(map(), map(), atom(), map()) :: map()
  def reconciliation_completed(settings, state, level, fields)
      when is_map(settings) and is_map(state) and is_atom(level) and is_map(fields) do
    emit(settings, level, Contract.event(:reconciliation_completed), nil, state, fields)
  end

  @spec candidate_selected(map(), Issue.t(), map(), RouteFacts.t()) :: map()
  def candidate_selected(settings, %Issue{} = issue, state, %RouteFacts{} = route_facts)
      when is_map(settings) and is_map(state) do
    emit(
      settings,
      :info,
      Contract.event(:candidate_selected),
      issue,
      state,
      route_facts
      |> RouteFields.source(settings, issue)
      |> Map.put(Fields.source_state(), route_facts.raw_state)
    )
  end

  @spec candidate_skipped(map(), Issue.t(), map(), atom(), map()) :: map()
  def candidate_skipped(settings, %Issue{} = issue, state, reason, extra_fields)
      when is_map(settings) and is_map(state) and is_atom(reason) and is_map(extra_fields) do
    candidate_skipped(settings, issue, state, reason, nil, extra_fields)
  end

  @spec candidate_skipped(map(), Issue.t(), map(), atom(), RouteFacts.t() | nil, map()) :: map()
  def candidate_skipped(settings, %Issue{} = issue, state, reason, route_facts, extra_fields)
      when is_map(settings) and is_map(state) and is_atom(reason) and is_map(extra_fields) do
    route_fields =
      case route_facts do
        %RouteFacts{} -> RouteFields.source(route_facts, settings, issue)
        _route_facts -> %{}
      end

    emit(
      settings,
      :info,
      Contract.event(:candidate_skipped),
      issue,
      state,
      %{Fields.skip_reason() => Contract.reason_name(reason)}
      |> Map.merge(route_fields)
      |> Map.merge(extra_fields)
    )
  end

  @spec change_proposal_located(map(), Issue.t(), map(), RouteFacts.t(), map()) :: map()
  def change_proposal_located(settings, %Issue{} = issue, state, %RouteFacts{} = route_facts, reference)
      when is_map(settings) and is_map(state) and is_map(reference) do
    emit(
      settings,
      :info,
      Contract.event(:change_proposal_located),
      issue,
      state,
      Map.merge(
        %{
          Fields.source_state() => route_facts.raw_state
        },
        RouteFields.source(route_facts, settings, issue)
        |> Map.merge(ChangeProposalFields.reference(reference))
      )
    )
  end

  @spec change_proposal_lookup_failed(map(), atom(), Issue.t(), map(), RouteFacts.t(), atom(), map()) ::
          map()
  def change_proposal_lookup_failed(
        settings,
        level,
        %Issue{} = issue,
        state,
        %RouteFacts{} = route_facts,
        reason,
        extra_fields
      )
      when is_map(settings) and is_atom(level) and is_map(state) and is_atom(reason) and
             is_map(extra_fields) do
    emit(
      settings,
      level,
      Contract.event(:change_proposal_lookup_failed),
      issue,
      state,
      Map.merge(
        %{
          Fields.source_state() => route_facts.raw_state,
          Fields.lookup_failure_reason() => Contract.reason_name(reason)
        },
        RouteFields.source(route_facts, settings, issue)
        |> Map.merge(extra_fields)
      )
    )
  end

  @spec decision(map(), Issue.t(), map(), RouteFacts.t(), Facts.t(), Decision.t()) :: map()
  def decision(settings, %Issue{} = issue, state, %RouteFacts{} = route_facts, %Facts{} = facts, %Decision{} = decision)
      when is_map(settings) and is_map(state) do
    emit(
      settings,
      :info,
      Contract.event(:decision),
      issue,
      state,
      ChangeProposalFields.decision(decision)
      |> Map.put(Fields.source_state(), route_facts.raw_state)
      |> Map.merge(ChangeProposalFields.facts(facts))
      |> Map.merge(RouteFields.source(route_facts, settings, issue))
      |> Map.merge(RouteFields.target(decision.target_route_ref))
    )
  end

  @spec transition(
          map(),
          atom(),
          atom(),
          Issue.t(),
          map(),
          RouteFacts.t(),
          Facts.t(),
          Decision.t(),
          map()
        ) :: map()
  def transition(settings, level, event, %Issue{} = issue, state, %RouteFacts{} = route_facts, %Facts{} = facts, %Decision{} = decision, extra_fields)
      when is_map(settings) and is_atom(level) and is_atom(event) and is_map(state) and is_map(extra_fields) do
    emit(
      settings,
      level,
      event,
      issue,
      state,
      Map.merge(
        ChangeProposalFields.decision(decision)
        |> Map.put(Fields.source_state(), route_facts.raw_state)
        |> Map.merge(ChangeProposalFields.transition_facts(facts)),
        ChangeProposalFields.transition_extra(extra_fields)
        |> Map.merge(RouteFields.source(route_facts, settings, issue))
        |> Map.merge(RouteFields.target(decision.target_route_ref))
      )
    )
  end

  defp emit(settings, level, event, issue, state, extra_fields) do
    Emitter.emit(
      level,
      event,
      BaseFields.merge(settings, issue, state, extra_fields)
    )
  end
end
