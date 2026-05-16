defmodule SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Fields do
  @moduledoc false

  @spec issue_id() :: String.t()
  def issue_id, do: "issue_id"

  @spec tracker_kind() :: String.t()
  def tracker_kind, do: "tracker_kind"

  @spec repo_provider_kind() :: String.t()
  def repo_provider_kind, do: "repo_provider_kind"

  @spec repository() :: String.t()
  def repository, do: "repository"

  @spec number() :: String.t()
  def number, do: "number"

  @spec change_proposal_id() :: String.t()
  def change_proposal_id, do: "change_proposal_id"

  @spec url() :: String.t()
  def url, do: "url"

  @spec branch() :: String.t()
  def branch, do: "branch"

  @spec head_sha() :: String.t()
  def head_sha, do: "head_sha"

  @spec last_observed_signature() :: String.t()
  def last_observed_signature, do: "last_observed_signature"

  @spec last_observed_at() :: String.t()
  def last_observed_at, do: "last_observed_at"

  @spec last_enqueued_at_ms() :: String.t()
  def last_enqueued_at_ms, do: "last_enqueued_at_ms"

  @spec registered_at_ms() :: String.t()
  def registered_at_ms, do: "registered_at_ms"

  @spec updated_at_ms() :: String.t()
  def updated_at_ms, do: "updated_at_ms"

  @spec observed_at() :: String.t()
  def observed_at, do: "observed_at"

  @spec provider_state() :: String.t()
  def provider_state, do: "provider_state"

  @spec review_summary() :: String.t()
  def review_summary, do: "review_summary"

  @spec check_summary() :: String.t()
  def check_summary, do: "check_summary"

  @spec mergeability_summary() :: String.t()
  def mergeability_summary, do: "mergeability_summary"

  @spec unresolved_actionable_feedback() :: String.t()
  def unresolved_actionable_feedback, do: "unresolved_actionable_feedback?"

  @spec error() :: String.t()
  def error, do: "error"

  @spec retryable() :: String.t()
  def retryable, do: "retryable?"
end
