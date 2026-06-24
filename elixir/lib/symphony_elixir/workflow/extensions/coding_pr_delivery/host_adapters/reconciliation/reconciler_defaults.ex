defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ReconcilerDefaults do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts

  @spec emit_event(atom(), atom(), map()) :: term()
  def emit_event(level, event, fields), do: ObservabilityLogger.emit(level, event, fields)

  @spec fetch_issues_by_states([String.t()], keyword()) :: term()
  def fetch_issues_by_states(states, opts), do: Tracker.fetch_issues_by_states(states, opts)

  @spec fetch_issue_states_by_ids([String.t()], keyword()) :: term()
  def fetch_issue_states_by_ids(issue_ids, opts), do: Tracker.fetch_issue_states_by_ids(issue_ids, opts)

  @spec provider_facts(map(), term(), keyword()) :: term()
  def provider_facts(repo, target, opts), do: ProviderFacts.facts(repo, target, opts)
end
