defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceKinds do
  @moduledoc """
  Structured execution-plan evidence kinds owned by Coding PR Delivery readiness.

  These strings are extension-owned protocol vocabulary. Tracker, repo-provider,
  and workflow platform modules must not own or reinterpret them.
  """

  @repo_commit "repo_commit"
  @repo_push "repo_push"
  @repo_diff "repo_diff"
  @repo_create_or_update_change_proposal "repo_create_or_update_change_proposal"
  @repo_change_proposal_snapshot "repo_change_proposal_snapshot"
  @repo_read_change_proposal_checks "repo_read_change_proposal_checks"
  @repo_read_change_proposal_discussion "repo_read_change_proposal_discussion"
  @tracker_attach_change_proposal "tracker_attach_change_proposal"
  @tracker_upsert_workpad "tracker_upsert_workpad"

  @repo_change_kinds [@repo_push, @repo_commit]
  @change_proposal_kinds [@repo_create_or_update_change_proposal, @repo_change_proposal_snapshot]
  @tracker_linkage_kinds [@tracker_attach_change_proposal]
  @checks_kinds [@repo_read_change_proposal_checks]
  @feedback_kinds [@repo_read_change_proposal_discussion]
  @handoff_record_kinds [@tracker_upsert_workpad]

  @spec repo_diff() :: String.t()
  def repo_diff, do: @repo_diff

  @spec repo_change_kinds() :: [String.t()]
  def repo_change_kinds, do: @repo_change_kinds

  @spec change_proposal_kinds() :: [String.t()]
  def change_proposal_kinds, do: @change_proposal_kinds

  @spec tracker_linkage_kinds() :: [String.t()]
  def tracker_linkage_kinds, do: @tracker_linkage_kinds

  @spec checks_kinds() :: [String.t()]
  def checks_kinds, do: @checks_kinds

  @spec feedback_kinds() :: [String.t()]
  def feedback_kinds, do: @feedback_kinds

  @spec handoff_record_kinds() :: [String.t()]
  def handoff_record_kinds, do: @handoff_record_kinds
end
