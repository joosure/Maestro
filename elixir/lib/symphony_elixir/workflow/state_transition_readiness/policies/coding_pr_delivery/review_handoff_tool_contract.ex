defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffToolContract do
  @moduledoc """
  Dynamic tool names that can produce coding PR delivery review-handoff readiness evidence.
  """

  @linear_upsert_workpad_tool "linear_upsert_workpad"
  @tapd_upsert_workpad_tool "tapd_upsert_workpad"
  @linear_attach_change_proposal_tool "linear_attach_change_proposal"
  @tapd_attach_change_proposal_tool "tapd_attach_change_proposal"
  @repo_commit_tool "repo_commit"
  @repo_push_tool "repo_push"
  @repo_diff_tool "repo_diff"
  @repo_create_or_update_change_proposal_tool "repo_create_or_update_change_proposal"
  @repo_read_change_proposal_checks_tool "repo_read_change_proposal_checks"
  @repo_read_change_proposal_discussion_tool "repo_read_change_proposal_discussion"
  @repo_change_proposal_snapshot_tool "repo_change_proposal_snapshot"

  @evidence_kind_by_tool %{
    @linear_upsert_workpad_tool => :workpad,
    @tapd_upsert_workpad_tool => :workpad,
    @linear_attach_change_proposal_tool => :tracker_change_proposal,
    @tapd_attach_change_proposal_tool => :tracker_change_proposal,
    @repo_commit_tool => :repo_commit,
    @repo_push_tool => :repo_push,
    @repo_diff_tool => :repo_diff_validation,
    @repo_create_or_update_change_proposal_tool => :repo_provider_change_proposal,
    @repo_read_change_proposal_checks_tool => :repo_provider_checks,
    @repo_read_change_proposal_discussion_tool => :repo_provider_feedback,
    @repo_change_proposal_snapshot_tool => :repo_provider_snapshot
  }

  @type evidence_kind ::
          :workpad
          | :tracker_change_proposal
          | :repo_commit
          | :repo_push
          | :repo_diff_validation
          | :repo_provider_change_proposal
          | :repo_provider_checks
          | :repo_provider_feedback
          | :repo_provider_snapshot

  @spec evidence_kind(String.t() | nil) :: evidence_kind() | nil
  def evidence_kind(tool) when is_binary(tool), do: Map.get(@evidence_kind_by_tool, tool)
  def evidence_kind(_tool), do: nil

  @spec evidence_tool_names() :: [String.t()]
  def evidence_tool_names, do: Map.keys(@evidence_kind_by_tool)

  @spec linear_upsert_workpad_tool() :: String.t()
  def linear_upsert_workpad_tool, do: @linear_upsert_workpad_tool

  @spec tapd_upsert_workpad_tool() :: String.t()
  def tapd_upsert_workpad_tool, do: @tapd_upsert_workpad_tool

  @spec repo_read_change_proposal_checks_tool() :: String.t()
  def repo_read_change_proposal_checks_tool, do: @repo_read_change_proposal_checks_tool
end
