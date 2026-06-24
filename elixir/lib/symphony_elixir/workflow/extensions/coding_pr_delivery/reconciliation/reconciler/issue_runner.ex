defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.IssueRunner do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input, as: RuntimeInput

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.{
    Config,
    Counters,
    Decision,
    Events,
    RouteContext,
    Transition
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Builder, as: ProviderFactsBuilder

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.{
    Candidates,
    Clients,
    Diagnostics,
    Options,
    TargetReference
  }

  @spec run(map(), Config.t(), term(), RuntimeInput.t(), map(), atom(), Options.t()) :: map()
  def run(settings, config, %Issue{} = issue, %RuntimeInput{} = runtime, extension_state, fetch_mode, %Options{} = options) do
    context = RouteContext.for_issue(settings, issue)
    route_facts = RouteContext.route_facts(issue, context)

    cond do
      is_nil(route_facts) ->
        Events.candidate_skipped(settings, issue, runtime, :route_unresolved, %{})
        extension_state

      not Config.source_route?(config, route_facts.route_key) ->
        Events.candidate_skipped(settings, issue, runtime, :source_route_mismatch, route_facts, %{
          source_state: route_facts.raw_state
        })

        Candidates.maybe_defer_known_target(issue, context, route_facts, fetch_mode, options)
        extension_state

      true ->
        reconcile_selected_issue(settings, config, issue, runtime, extension_state, context, route_facts, options)
    end
  end

  def run(_settings, _config, _issue, _runtime, extension_state, _fetch_mode, %Options{}), do: extension_state

  defp reconcile_selected_issue(settings, config, issue, runtime, extension_state, context, route_facts, %Options{} = options) do
    Events.candidate_selected(settings, issue, runtime, route_facts)

    case TargetReference.lookup(issue, options) do
      {:ok, nil} ->
        Events.change_proposal_lookup_failed(settings, :info, issue, runtime, route_facts, :not_found, %{})
        inspect_change_proposal(settings, config, issue, runtime, extension_state, context, route_facts, nil, options)

      {:ok, target} ->
        Events.change_proposal_located(settings, issue, runtime, route_facts, target)
        inspect_change_proposal(settings, config, issue, runtime, extension_state, context, route_facts, target, options)

      {:error, reason} ->
        error_fields = %{error: Diagnostics.error_string(reason)}

        Events.change_proposal_lookup_failed(settings, :warning, issue, runtime, route_facts, :error, error_fields)

        Events.candidate_skipped(
          settings,
          issue,
          runtime,
          :change_proposal_reference_unavailable,
          route_facts,
          error_fields
        )

        extension_state
    end
  end

  defp inspect_change_proposal(settings, config, issue, runtime, extension_state, context, route_facts, target, %Options{} = options) do
    facts = change_proposal_facts(settings.repo, target, options)
    {extension_state, failed_checks_count} = Counters.update_failed_check_counter(extension_state, issue, facts)

    decision =
      Decision.decide(config, route_facts, issue, facts, %{
        failed_checks_count: failed_checks_count
      })

    Events.decision(settings, issue, runtime, route_facts, facts, decision)
    _runtime = Transition.apply(settings, issue, runtime, context, route_facts, facts, decision, options.raw_opts)

    extension_state
  end

  defp change_proposal_facts(repo_config, target, %Options{} = options) do
    case Clients.change_proposal_facts(repo_config, target, options) do
      {:ok, facts} ->
        facts

      {:error, reason} ->
        ProviderFactsBuilder.error(repo_config, :provider_facts, target_for_error(target), reason)
    end
  end

  defp target_for_error(target) when is_map(target), do: target
  defp target_for_error(_target), do: %{}
end
