defmodule SymphonyElixir.ChangeProposalReconciliation.Events do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.Contract
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.{Config, Decision, Facts}
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RouteFacts

  @spec config_invalid(map(), map(), term()) :: map()
  def config_invalid(settings, state, reason) when is_map(settings) and is_map(state) do
    emit(settings, :warning, Contract.event(:config_invalid), nil, state, %{
      error: inspect(reason)
    })
  end

  @spec reconciliation_started(map(), map(), Config.t(), [String.t()]) :: map()
  def reconciliation_started(settings, state, %Config{} = config, source_raw_states)
      when is_map(settings) and is_map(state) and is_list(source_raw_states) do
    emit(settings, :info, Contract.event(:reconciliation_started), nil, state, %{
      source_routes: config.source_routes,
      source_states: source_raw_states
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
    emit(settings, :info, Contract.event(:candidate_selected), issue, state, %{
      source_route: route_facts.route_key,
      source_state: route_facts.raw_state
    })
  end

  @spec candidate_skipped(map(), Issue.t(), map(), atom(), map()) :: map()
  def candidate_skipped(settings, %Issue{} = issue, state, reason, extra_fields)
      when is_map(settings) and is_map(state) and is_atom(reason) and is_map(extra_fields) do
    emit(
      settings,
      :info,
      Contract.event(:candidate_skipped),
      issue,
      state,
      Map.merge(%{skip_reason: Contract.reason_name(reason)}, extra_fields)
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
          source_route: route_facts.route_key,
          source_state: route_facts.raw_state
        },
        change_proposal_reference_fields(reference)
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
          source_route: route_facts.route_key,
          source_state: route_facts.raw_state,
          lookup_failure_reason: Contract.reason_name(reason)
        },
        extra_fields
      )
    )
  end

  @spec decision(map(), Issue.t(), map(), RouteFacts.t(), Facts.t(), Decision.t()) :: map()
  def decision(settings, %Issue{} = issue, state, %RouteFacts{} = route_facts, %Facts{} = facts, %Decision{} = decision)
      when is_map(settings) and is_map(state) do
    emit(settings, :info, Contract.event(:decision), issue, state, %{
      decision: decision.action,
      reason: decision.reason,
      source_route: route_facts.route_key,
      source_state: route_facts.raw_state,
      target_route: decision.target_route,
      repo_provider_kind: facts.provider_kind,
      repository: facts.repository,
      change_proposal_number: facts.number,
      change_proposal_url: facts.url,
      change_proposal_branch: facts.branch,
      head_sha: facts.head_sha,
      provider_state: facts.provider_state,
      review_summary: facts.review_summary,
      check_summary: facts.check_summary,
      mergeability_summary: facts.mergeability_summary,
      retryable: facts.retryable?,
      error: if(is_nil(facts.error), do: nil, else: inspect(facts.error))
    })
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
        %{
          source_route: route_facts.route_key,
          source_state: route_facts.raw_state,
          target_route: decision.target_route,
          repo_provider_kind: facts.provider_kind,
          change_proposal_number: facts.number,
          change_proposal_url: facts.url,
          head_sha: facts.head_sha,
          decision: decision.action,
          reason: decision.reason
        },
        normalize_transition_fields(extra_fields)
      )
    )
  end

  defp normalize_transition_fields(fields) when is_map(fields) do
    case Map.fetch(fields, :skip_reason) do
      {:ok, reason} -> Map.put(fields, :skip_reason, Contract.reason_name(reason))
      :error -> fields
    end
  end

  defp change_proposal_reference_fields(reference) when is_map(reference) do
    %{
      change_proposal_number: reference_value(reference, :number),
      change_proposal_url: reference_value(reference, :url),
      change_proposal_branch: reference_value(reference, :branch)
    }
  end

  defp reference_value(reference, key) when is_map(reference) and is_atom(key) do
    Map.get(reference, key) || Map.get(reference, Atom.to_string(key))
  end

  defp emit(settings, level, event, issue, state, extra_fields) do
    profile = profile_fields(settings)

    ObservabilityLogger.emit(
      level,
      event,
      extra_fields
      |> Map.put_new(:repo_provider_kind, RepoProvider.current_kind(settings.repo))
      |> Map.merge(profile)
      |> event_fields(settings, issue, state)
    )
  end

  defp event_fields(fields, settings, issue, state) when is_map(fields) do
    %{
      component: Contract.component(),
      tracker_kind: tracker_kind(settings),
      issue_id: issue_id(issue),
      issue_identifier: issue_identifier(issue),
      running_count: running_count(state),
      claimed_count: claimed_count(state),
      available_slots: available_slots_for_event(state),
      max_concurrent_agents: max_concurrent_agents_for_event(state)
    }
    |> Map.merge(fields)
  end

  defp tracker_kind(%{tracker: tracker}), do: TrackerConfig.kind(tracker)
  defp tracker_kind(%{"tracker" => tracker}), do: TrackerConfig.kind(tracker)
  defp tracker_kind(_settings), do: nil

  defp profile_fields(settings) do
    case ProfileRegistry.resolve(settings.workflow.profile) do
      {:ok, profile_context} ->
        %{
          workflow_profile_kind: profile_context.kind,
          workflow_profile_version: profile_context.version
        }

      {:error, _reason} ->
        %{}
    end
  end

  defp issue_id(%Issue{id: issue_id}), do: issue_id
  defp issue_id(_issue), do: nil

  defp issue_identifier(%Issue{identifier: identifier}), do: identifier
  defp issue_identifier(_issue), do: nil

  defp running_count(%{running: running}) when is_map(running), do: map_size(running)
  defp running_count(_state), do: nil

  defp claimed_count(%{claimed: claimed}) when is_struct(claimed, MapSet), do: MapSet.size(claimed)
  defp claimed_count(_state), do: nil

  defp available_slots_for_event(state) when is_map(state) do
    case max_concurrent_agents_for_event(state) do
      max when is_integer(max) -> max(max - running_count_for_slots(state), 0)
      _max -> nil
    end
  end

  defp max_concurrent_agents_for_event(%{max_concurrent_agents: max}) when is_integer(max), do: max
  defp max_concurrent_agents_for_event(_state), do: nil

  defp running_count_for_slots(%{running: running}) when is_map(running), do: map_size(running)
  defp running_count_for_slots(_state), do: 0
end
