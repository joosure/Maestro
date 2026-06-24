defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults do
  @moduledoc false

  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts

  @spec settings() :: {:ok, map()} | {:error, term()}
  def settings, do: Config.settings()

  @spec emit_event(atom(), atom(), map()) :: term()
  def emit_event(level, event, fields), do: ObservabilityLogger.emit(level, event, fields)

  @spec fetch_issue_states_by_ids(map(), [String.t()], keyword()) :: term()
  def fetch_issue_states_by_ids(tracker, issue_ids, opts), do: Tracker.fetch_issue_states_by_ids(tracker, issue_ids, opts)

  @spec fetch_issues_by_states([String.t()], keyword()) :: term()
  def fetch_issues_by_states(states, opts), do: Tracker.fetch_issues_by_states(states, opts)

  @spec normalize_issue_id(map(), String.t()) :: String.t()
  def normalize_issue_id(tracker, issue_id), do: Tracker.normalize_issue_id(tracker, issue_id) || issue_id

  @spec dynamic_tools(map()) :: [map()]
  def dynamic_tools(tracker), do: Tracker.dynamic_tools(tracker)

  @spec tracker_kind(map()) :: String.t() | nil
  def tracker_kind(tracker), do: Tracker.Config.kind(tracker)

  @spec repo_provider_kind(map()) :: String.t() | nil
  def repo_provider_kind(repo), do: RepoProvider.current_kind(repo)

  @spec repo_repository(map()) :: String.t() | nil
  def repo_repository(repo), do: RepoConfig.repository(repo)

  @spec provider_facts(map(), term(), keyword()) :: term()
  def provider_facts(repo, reference, opts), do: ProviderFacts.facts(repo, reference, opts)

  @spec enqueue_issue_ids([String.t()], keyword()) :: term()
  def enqueue_issue_ids(issue_ids, opts), do: Inbox.enqueue_issue_ids(issue_ids, opts)
end
