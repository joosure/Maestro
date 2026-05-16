defmodule SymphonyElixir.Orchestrator.Dispatch.RoutePreparation do
  @moduledoc false

  alias SymphonyElixir.Config
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch.{Context, Eligibility}
  alias SymphonyElixir.RepoProvider.ChangeProposalInspector
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.ChangeProposalReference
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Facts, as: ChangeProposalFacts
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.Readiness
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
    case readiness_gate_action(issue, context, opts) do
      {:skip, _gate, prepared_issue} ->
        {:skip, prepared_issue}

      {:continue, prepared_issue} ->
        prepare_route_policy(prepared_issue, issue_fetcher, state_updater, context, opts)
    end
  end

  def prepare(issue, _issue_fetcher, _state_updater, _context, _opts), do: {:ok, issue}

  defp prepare_route_policy(issue, issue_fetcher, state_updater, context, opts) do
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

  defp readiness_gate_action(%Issue{} = issue, context, opts) when is_map(context) and is_list(opts) do
    settings = Context.workflow_settings(context)
    available_capabilities = Context.available_capabilities(context)

    facts = readiness_facts(issue, settings, available_capabilities)
    {facts, prepared_issue} = maybe_enrich_readiness_facts(issue, context, opts, facts)

    gate = Map.get(facts, "gate", %{})

    if readiness_gate_blocks_dispatch?(gate) do
      emit_readiness_gate(Keyword.get(opts, :emit_readiness_gate), issue, facts)
      {:skip, gate, prepared_issue}
    else
      {:continue, prepared_issue}
    end
  end

  defp readiness_gate_action(issue, _context, _opts), do: {:continue, issue}

  defp readiness_facts(issue, settings, available_capabilities, evidence \\ nil)

  defp readiness_facts(%Issue{} = issue, settings, available_capabilities, nil) do
    Readiness.facts(issue,
      settings: settings,
      available_capabilities: available_capabilities
    )
  end

  defp readiness_facts(%Issue{} = issue, settings, available_capabilities, evidence) when is_map(evidence) do
    Readiness.facts(issue,
      settings: settings,
      available_capabilities: available_capabilities,
      evidence: evidence
    )
  end

  defp maybe_enrich_readiness_facts(%Issue{} = issue, context, opts, facts) do
    if merge_gate?(facts) do
      evidence = readiness_evidence(issue, context, facts, opts)

      if map_size(evidence) > 0 do
        settings = Context.workflow_settings(context)
        available_capabilities = Context.available_capabilities(context)

        enriched_issue = put_completion_evidence(issue, evidence)
        enriched_facts = readiness_facts(enriched_issue, settings, available_capabilities, evidence)

        {enriched_facts, enriched_issue}
      else
        {facts, issue}
      end
    else
      {facts, issue}
    end
  end

  defp merge_gate?(%{"gate" => %{"gate" => "merge"}}), do: true
  defp merge_gate?(_facts), do: false

  defp readiness_evidence(%Issue{} = issue, context, facts, opts) do
    cond do
      is_map(Keyword.get(opts, :readiness_evidence)) ->
        Keyword.fetch!(opts, :readiness_evidence)

      is_function(Keyword.get(opts, :readiness_evidence_fn)) ->
        opts
        |> Keyword.fetch!(:readiness_evidence_fn)
        |> call_readiness_evidence_fn(issue, context, facts)
        |> normalize_readiness_evidence_result()

      true ->
        default_readiness_evidence(issue, opts)
    end
  end

  defp call_readiness_evidence_fn(fun, issue, context, facts) when is_function(fun, 3),
    do: fun.(issue, context, facts)

  defp call_readiness_evidence_fn(fun, issue, context, _facts) when is_function(fun, 2),
    do: fun.(issue, context)

  defp call_readiness_evidence_fn(fun, issue, _context, _facts) when is_function(fun, 1),
    do: fun.(issue)

  defp call_readiness_evidence_fn(_fun, _issue, _context, _facts), do: %{}

  defp normalize_readiness_evidence_result({:ok, evidence}) when is_map(evidence), do: evidence
  defp normalize_readiness_evidence_result(evidence) when is_map(evidence), do: evidence
  defp normalize_readiness_evidence_result(_result), do: %{}

  defp default_readiness_evidence(%Issue{} = issue, opts) do
    with {:ok, settings} <- current_settings(),
         repo when is_map(repo) <- Map.get(settings, :repo),
         {:ok, %ChangeProposalReference{} = reference} <- change_proposal_reference(issue, repo, opts),
         target when map_size(target) > 0 <- change_proposal_target(reference),
         %ChangeProposalFacts{} = facts <-
           ChangeProposalInspector.facts(repo, target, Keyword.get(opts, :change_proposal_inspector_opts, [])),
         true <- land_ready_facts?(facts) do
      change_proposal_facts_to_evidence(facts, issue)
    else
      _reason -> %{}
    end
  end

  defp current_settings do
    {:ok, Config.settings!()}
  rescue
    _reason -> :error
  end

  defp change_proposal_reference(%Issue{} = issue, repo, opts) when is_map(repo) do
    case Tracker.change_proposal_reference(issue) do
      %ChangeProposalReference{} = reference ->
        {:ok, reference}

      nil ->
        if repo_context_available?(repo) do
          Tracker.fetch_change_proposal_reference(
            issue,
            Keyword.get(opts, :change_proposal_reference_opts, [])
          )
        else
          {:ok, nil}
        end
    end
  end

  defp repo_context_available?(repo) when is_map(repo) do
    [RepoConfig.repository(repo), RepoConfig.remote_url(repo), RepoConfig.path(repo)]
    |> Enum.any?(&present?/1)
  end

  defp change_proposal_target(%ChangeProposalReference{} = reference) do
    %{}
    |> put_present(:number, reference.number)
    |> put_present(:url, reference.url)
    |> put_present(:branch, reference.branch)
  end

  defp change_proposal_facts_to_evidence(%ChangeProposalFacts{} = facts, %Issue{} = issue) do
    %{
      change_proposal: %{
        url: facts.url,
        number: facts.number,
        target: facts.number || facts.url || facts.branch,
        branch: facts.branch,
        provider_state: atom_name(facts.provider_state),
        linked_issue: true,
        tracker_linked: true
      },
      repo: %{
        repository: facts.repository,
        branch: facts.branch,
        head_sha: facts.head_sha,
        diff_present: present?(facts.head_sha)
      },
      checks: %{
        read: facts.check_summary != :unknown,
        status: atom_name(facts.check_summary),
        check_summary: atom_name(facts.check_summary),
        passing: facts.check_summary == :passing
      },
      review: %{
        approved: facts.review_summary == :approved,
        status: atom_name(facts.review_summary),
        review_summary: atom_name(facts.review_summary)
      },
      tracker: %{
        state: issue.state,
        change_proposal_attached: true,
        merge_approved: land_ready_facts?(facts)
      }
    }
  end

  defp land_ready_facts?(%ChangeProposalFacts{} = facts) do
    facts.provider_state == :open and
      facts.review_summary == :approved and
      facts.check_summary == :passing and
      facts.mergeability_summary == :mergeable and
      facts.unresolved_actionable_feedback? == false
  end

  defp put_completion_evidence(%Issue{} = issue, evidence) when is_map(evidence) do
    workflow = normalize_map(issue.workflow)
    existing_evidence = workflow |> map_field(:completion_evidence) |> normalize_map()

    %Issue{
      issue
      | workflow:
          workflow
          |> Map.delete("completion_evidence")
          |> Map.put(:completion_evidence, Map.merge(existing_evidence, evidence))
    }
  end

  defp readiness_gate_blocks_dispatch?(%{"status" => "blocked", "gate" => gate})
       when gate in ["merge", "capability"],
       do: true

  defp readiness_gate_blocks_dispatch?(_gate), do: false

  defp emit_readiness_gate(readiness_gate_emitter, %Issue{} = issue, facts)
       when is_function(readiness_gate_emitter, 3) and is_map(facts) do
    readiness_gate_emitter.(issue, Map.get(facts, "gate", %{}), facts)
  end

  defp emit_readiness_gate(_readiness_gate_emitter, _issue, _facts), do: :ok

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

  defp put_present(map, _key, nil), do: map

  defp put_present(map, key, value) when is_binary(value) do
    case String.trim(value) do
      "" -> map
      _value -> Map.put(map, key, value)
    end
  end

  defp put_present(map, key, value) when is_integer(value), do: Map.put(map, key, value)

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil

  defp atom_name(value) when is_atom(value), do: Atom.to_string(value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_integer(value), do: true
  defp present?(_value), do: false
end
