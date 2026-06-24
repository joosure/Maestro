defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.EvidenceKind do
  @moduledoc """
  Coding PR Delivery structured-plan evidence kind contract.

  Keep raw typed-tool payload fields, normalized payload fields, status values,
  and URL policy values in focused sibling contracts.
  """

  @repo_create_or_update_change_proposal "repo_create_or_update_change_proposal"
  @repo_change_proposal_snapshot "repo_change_proposal_snapshot"
  @repo_read_change_proposal_checks "repo_read_change_proposal_checks"
  @repo_read_change_proposal_discussion "repo_read_change_proposal_discussion"
  @tracker_attach_change_proposal "tracker_attach_change_proposal"

  @spec repo_create_or_update_change_proposal_evidence_kind() :: String.t()
  def repo_create_or_update_change_proposal_evidence_kind, do: @repo_create_or_update_change_proposal

  @spec repo_change_proposal_snapshot_evidence_kind() :: String.t()
  def repo_change_proposal_snapshot_evidence_kind, do: @repo_change_proposal_snapshot

  @spec repo_read_change_proposal_checks_evidence_kind() :: String.t()
  def repo_read_change_proposal_checks_evidence_kind, do: @repo_read_change_proposal_checks

  @spec repo_read_change_proposal_discussion_evidence_kind() :: String.t()
  def repo_read_change_proposal_discussion_evidence_kind, do: @repo_read_change_proposal_discussion

  @spec tracker_attach_change_proposal_evidence_kind() :: String.t()
  def tracker_attach_change_proposal_evidence_kind, do: @tracker_attach_change_proposal
end
