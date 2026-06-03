defmodule SymphonyElixir.ChangeProposalReconciliation.Reconciler do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.{Contract, Counters, Events, KnownTarget, RouteContext, TrackerCallOptions, Transition}
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider.ChangeProposalInspector
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.ChangeProposalReference

  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.{
    Config,
    Decision
  }

  alias SymphonyElixir.Workflow.RouteRef

  @targeted_issue_ids_limit 100
  @spec reconcile(map(), map(), keyword()) :: map()
  def reconcile(settings, state, opts \\ []) when is_map(settings) and is_map(state) and is_list(opts) do
    case Config.from_settings(settings) do
      {:ok, %Config{enabled?: false}} ->
        state

      {:ok, %Config{} = config} ->
        do_reconcile(settings, config, state, opts)

      {:error, reason} ->
        Events.config_invalid(settings, state, reason)
        state
    end
  end

  defp do_reconcile(settings, config, state, opts) do
    started_at_ms = System.monotonic_time(:millisecond)
    source_raw_states = RouteContext.source_raw_states(settings, config)
    targeted_issue_ids = runtime_targeted_issue_ids(opts, config.max_processed_candidate_issues_per_cycle)

    Events.reconciliation_started(settings, state, config, source_raw_states)

    case fetch_candidate_issues(source_raw_states, targeted_issue_ids, config, opts) do
      {:ok, fetch_mode, issues} ->
        candidate_issues = reject_running_issues(issues, state, fetch_mode, opts)

        {updated_state, processed_count} =
          candidate_issues
          |> Enum.take(config.max_processed_candidate_issues_per_cycle)
          |> Enum.reduce({state, 0}, fn issue, {state_acc, count} ->
            {reconcile_issue(settings, config, issue, state_acc, fetch_mode, opts), count + 1}
          end)

        Events.reconciliation_completed(settings, updated_state, :info, %{
          status: Contract.reconciliation_status(:ok),
          candidate_fetch_mode: fetch_mode,
          targeted_issue_count: length(targeted_issue_ids),
          source_state_count: length(source_raw_states),
          candidate_count: length(issues),
          processed_count: processed_count,
          duration_ms: elapsed_ms(started_at_ms)
        })

        updated_state

      {:error, reason} ->
        Events.reconciliation_completed(settings, state, :warning, %{
          status: Contract.reconciliation_status(:tracker_error),
          error: inspect(reason),
          targeted_issue_count: length(targeted_issue_ids),
          duration_ms: elapsed_ms(started_at_ms)
        })

        state
    end
  end

  defp reconcile_issue(settings, config, %Issue{} = issue, state, fetch_mode, opts) do
    context = RouteContext.for_issue(settings, issue)
    route_facts = RouteContext.route_facts(issue, context)

    cond do
      is_nil(route_facts) ->
        Events.candidate_skipped(settings, issue, state, :route_unresolved, %{})
        state

      not Config.source_route?(config, route_facts.route_key) ->
        Events.candidate_skipped(settings, issue, state, :source_route_mismatch, route_facts, %{
          source_state: route_facts.raw_state
        })

        maybe_defer_targeted_known_target(issue, context, route_facts, fetch_mode, opts)
        state

      true ->
        reconcile_selected_issue(settings, config, issue, state, context, route_facts, opts)
    end
  end

  defp reconcile_issue(_settings, _config, _issue, state, _fetch_mode, _opts), do: state

  defp reconcile_selected_issue(settings, config, issue, state, context, route_facts, opts) do
    Events.candidate_selected(settings, issue, state, route_facts)

    case change_proposal_reference(settings, issue, opts) do
      {:ok, nil} ->
        Events.change_proposal_lookup_failed(settings, :info, issue, state, route_facts, :not_found, %{})
        inspect_change_proposal(settings, config, issue, state, context, route_facts, nil, opts)

      {:ok, target} ->
        Events.change_proposal_located(settings, issue, state, route_facts, target)
        inspect_change_proposal(settings, config, issue, state, context, route_facts, target, opts)

      {:error, reason} ->
        Events.change_proposal_lookup_failed(settings, :warning, issue, state, route_facts, :error, %{
          error: inspect(reason)
        })

        Events.candidate_skipped(settings, issue, state, :change_proposal_reference_unavailable, route_facts, %{
          error: inspect(reason)
        })

        state
    end
  end

  defp inspect_change_proposal(settings, config, issue, state, context, route_facts, target, opts) do
    facts = change_proposal_facts(settings.repo, target, opts)
    {state, failed_checks_count} = Counters.update_failed_check_counter(state, issue, facts)

    decision =
      Decision.decide(config, route_facts, issue, facts, %{
        failed_checks_count: failed_checks_count
      })

    Events.decision(settings, issue, state, route_facts, facts, decision)
    Transition.apply(settings, issue, state, context, route_facts, facts, decision, opts)
  end

  defp change_proposal_reference(settings, issue, opts) do
    case Keyword.get(opts, :change_proposal_reference_fn) do
      fun when is_function(fun, 2) ->
        normalize_change_proposal_reference_result(fun.(issue, opts))

      _fun ->
        default_change_proposal_reference(settings, issue, opts)
    end
  end

  defp default_change_proposal_reference(_settings, %Issue{} = issue, opts) do
    with nil <- Tracker.change_proposal_reference(issue),
         nil <- known_target_reference(issue, opts) do
      {:ok, nil}
    else
      %ChangeProposalReference{} = reference -> {:ok, reference}
    end
  end

  defp known_target_reference(%Issue{id: issue_id}, opts) when is_binary(issue_id) do
    case KnownTarget.Registry.get(issue_id, known_target_registry_opts(opts)) do
      %KnownTarget{} = target -> KnownTarget.reference(target)
      _target -> nil
    end
  end

  defp known_target_registry_opts(opts) do
    case Keyword.fetch(opts, :known_target_registry) do
      {:ok, registry} -> [server: registry]
      :error -> []
    end
  end

  defp normalize_change_proposal_reference_result({:ok, _target} = result), do: result
  defp normalize_change_proposal_reference_result({:error, _reason} = error), do: error
  defp normalize_change_proposal_reference_result(nil), do: {:ok, nil}
  defp normalize_change_proposal_reference_result(target) when is_map(target), do: {:ok, target}

  defp change_proposal_facts(repo_config, target, opts) do
    Keyword.get(opts, :change_proposal_facts_fn, &ChangeProposalInspector.facts/3).(
      repo_config,
      target,
      opts
    )
  end

  defp reject_running_issues(issues, state, fetch_mode, opts) when is_list(issues) and is_map(state) do
    running_ids = state |> Map.get(:running, %{}) |> Map.keys() |> MapSet.new()
    claimed_ids = Map.get(state, :claimed, MapSet.new())

    {deferred_issue_ids, candidate_issues} =
      Enum.reduce(issues, {[], []}, fn
        %Issue{id: issue_id} = issue, {deferred, candidates} when is_binary(issue_id) ->
          if MapSet.member?(running_ids, issue_id) or MapSet.member?(claimed_ids, issue_id) do
            {[issue_id | deferred], candidates}
          else
            {deferred, [issue | candidates]}
          end

        _issue, acc ->
          acc
      end)

    defer_targeted_issue_ids(Enum.reverse(deferred_issue_ids), fetch_mode, opts, %{
      reason: :running_or_claimed
    })

    Enum.reverse(candidate_issues)
  end

  defp reject_running_issues(_issues, _state, _fetch_mode, _opts), do: []

  defp defer_targeted_issue_ids([], _fetch_mode, _opts, _details), do: :ok

  defp defer_targeted_issue_ids(issue_ids, :targeted_issue_ids, opts, details)
       when is_list(issue_ids) and is_list(opts) and is_map(details) do
    case Keyword.get(opts, :defer_targeted_issue_ids_fn) do
      fun when is_function(fun, 2) ->
        issue_ids
        |> fun.(details)
        |> emit_candidate_suspended(issue_ids, details, opts)

        :ok

      fun when is_function(fun, 1) ->
        _result = fun.(issue_ids)
        :ok

      _other ->
        :ok
    end
  end

  defp defer_targeted_issue_ids(_issue_ids, _fetch_mode, _opts, _details), do: :ok

  defp maybe_defer_targeted_known_target(%Issue{id: issue_id} = issue, context, route_facts, :targeted_issue_ids, opts)
       when is_binary(issue_id) do
    if route_facts.action != :stop and not is_nil(known_target_reference(issue, opts)) do
      defer_targeted_issue_ids([issue_id], :targeted_issue_ids, opts, %{
        reason: :source_route_pending,
        route_ref: RouteRef.new!(context.profile_context, route_facts.route_key)
      })
    else
      :ok
    end
  end

  defp maybe_defer_targeted_known_target(_issue, _context, _route_facts, _fetch_mode, _opts), do: :ok

  defp fetch_issues_by_states(states, opts) do
    Keyword.get(opts, :fetch_issues_by_states_fn, &Tracker.fetch_issues_by_states/2).(
      states,
      TrackerCallOptions.fetch(opts)
    )
  end

  defp emit_candidate_suspended({:ok, result}, issue_ids, details, opts) when is_map(result) do
    suspended_issue_ids = Map.get(result, :suspended_issue_ids, [])

    if Map.get(result, :suspended_count, 0) > 0 and suspended_issue_ids != [] do
      opts
      |> Keyword.get(:emit_event_fn, &ObservabilityLogger.emit/3)
      |> then(fn emit ->
        Enum.each(suspended_issue_ids, fn issue_id ->
          emit.(:info, Contract.event(:candidate_suspended), %{
            component: Contract.component(),
            issue_id: issue_id,
            reason: Contract.reason_name(Map.get(details, :reason, :defer_policy_exceeded)),
            source_workflow_profile: route_ref_value(details, :profile_kind),
            source_workflow_profile_version: route_ref_value(details, :profile_version),
            source_workflow_route_key: route_ref_value(details, :route_key),
            requested_issue_count: length(issue_ids),
            suspended_count: Map.get(result, :suspended_count)
          })
        end)
      end)
    end

    :ok
  end

  defp emit_candidate_suspended(_result, _issue_ids, _details, _opts), do: :ok

  defp route_ref_value(%{route_ref: %RouteRef{} = route_ref}, :profile_kind), do: route_ref.profile_kind
  defp route_ref_value(%{route_ref: %RouteRef{} = route_ref}, :profile_version), do: route_ref.profile_version
  defp route_ref_value(%{route_ref: %RouteRef{} = route_ref}, :route_key), do: Atom.to_string(route_ref.route_key)
  defp route_ref_value(_details, _field), do: nil

  defp fetch_candidate_issues(_source_raw_states, [], %Config{candidate_discovery: :runtime_targeted}, _opts) do
    {:ok, :runtime_targeted_empty, []}
  end

  defp fetch_candidate_issues(source_raw_states, [], %Config{}, opts) do
    case fetch_issues_by_states(source_raw_states, opts) do
      {:ok, issues} -> {:ok, :source_route_scan, issues}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_candidate_issues(_source_raw_states, targeted_issue_ids, %Config{}, opts)
       when is_list(targeted_issue_ids) do
    case fetch_issue_states_by_ids(targeted_issue_ids, opts) do
      {:ok, issues} -> {:ok, :targeted_issue_ids, issues}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_issue_states_by_ids(issue_ids, opts) do
    Keyword.get(opts, :fetch_issue_states_by_ids_fn, &Tracker.fetch_issue_states_by_ids/2).(
      issue_ids,
      TrackerCallOptions.fetch(opts)
    )
  end

  defp runtime_targeted_issue_ids(opts, limit) when is_list(opts) and is_integer(limit) do
    limit = min(limit, @targeted_issue_ids_limit)

    opts
    |> targeted_issue_ids_input(limit)
    |> normalize_targeted_issue_ids(limit)
  end

  defp targeted_issue_ids_input(opts, limit) when is_list(opts) and is_integer(limit) do
    case Keyword.fetch(opts, :targeted_issue_ids) do
      {:ok, values} ->
        values

      :error ->
        opts
        |> Keyword.get(:targeted_issue_ids_fn)
        |> targeted_issue_ids_from_fun(limit)
    end
  end

  defp targeted_issue_ids_from_fun(fun, limit) when is_function(fun, 1), do: fun.(limit)
  defp targeted_issue_ids_from_fun(fun, _limit) when is_function(fun, 0), do: fun.()
  defp targeted_issue_ids_from_fun(_fun, _limit), do: []

  defp normalize_targeted_issue_ids({:ok, values}, limit), do: normalize_targeted_issue_ids(values, limit)
  defp normalize_targeted_issue_ids(result, _limit) when not is_list(result), do: []

  defp normalize_targeted_issue_ids(values, limit) when is_list(values) do
    limit = max(limit, 0)

    values
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> []
          trimmed -> [trimmed]
        end

      _value ->
        []
    end)
    |> Enum.uniq()
    |> Enum.take(limit)
  end

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    System.monotonic_time(:millisecond) - started_at_ms
  end
end
