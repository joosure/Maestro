defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Contract do
  @moduledoc false

  @component "workflow.extensions.coding_pr_delivery.readiness.evidence_provider"
  @error_code "coding_pr_delivery_readiness_evidence_provider_error"
  @error_event :coding_pr_delivery_readiness_evidence_provider_error
  @emit_event_fn_key :emit_event_fn
  @options_operation "options"
  @evidence_operation "evidence"

  @change_proposal_key :change_proposal
  @repo_key :repo
  @checks_key :checks
  @review_key :review
  @tracker_key :tracker

  @url_key :url
  @number_key :number
  @target_key :target
  @branch_key :branch
  @provider_state_key :provider_state
  @linked_issue_key :linked_issue
  @tracker_linked_key :tracker_linked
  @repository_key :repository
  @head_sha_key :head_sha
  @diff_present_key :diff_present
  @read_key :read
  @status_key :status
  @check_summary_key :check_summary
  @passing_key :passing
  @approved_key :approved
  @review_summary_key :review_summary
  @state_key :state
  @change_proposal_attached_key :change_proposal_attached
  @merge_approved_key :merge_approved

  @provider_state_open :open
  @review_summary_approved :approved
  @check_summary_passing :passing
  @mergeability_summary_mergeable :mergeable
  @summary_unknown :unknown

  @spec component() :: String.t()
  def component, do: @component

  @spec error_code() :: String.t()
  def error_code, do: @error_code

  @spec error_event() :: atom()
  def error_event, do: @error_event

  @spec emit_event_fn_key() :: atom()
  def emit_event_fn_key, do: @emit_event_fn_key

  @spec options_operation() :: String.t()
  def options_operation, do: @options_operation

  @spec evidence_operation() :: String.t()
  def evidence_operation, do: @evidence_operation

  @spec change_proposal_key() :: atom()
  def change_proposal_key, do: @change_proposal_key

  @spec repo_key() :: atom()
  def repo_key, do: @repo_key

  @spec checks_key() :: atom()
  def checks_key, do: @checks_key

  @spec review_key() :: atom()
  def review_key, do: @review_key

  @spec tracker_key() :: atom()
  def tracker_key, do: @tracker_key

  @spec url_key() :: atom()
  def url_key, do: @url_key

  @spec number_key() :: atom()
  def number_key, do: @number_key

  @spec target_key() :: atom()
  def target_key, do: @target_key

  @spec branch_key() :: atom()
  def branch_key, do: @branch_key

  @spec provider_state_key() :: atom()
  def provider_state_key, do: @provider_state_key

  @spec linked_issue_key() :: atom()
  def linked_issue_key, do: @linked_issue_key

  @spec tracker_linked_key() :: atom()
  def tracker_linked_key, do: @tracker_linked_key

  @spec repository_key() :: atom()
  def repository_key, do: @repository_key

  @spec head_sha_key() :: atom()
  def head_sha_key, do: @head_sha_key

  @spec diff_present_key() :: atom()
  def diff_present_key, do: @diff_present_key

  @spec read_key() :: atom()
  def read_key, do: @read_key

  @spec status_key() :: atom()
  def status_key, do: @status_key

  @spec check_summary_key() :: atom()
  def check_summary_key, do: @check_summary_key

  @spec passing_key() :: atom()
  def passing_key, do: @passing_key

  @spec approved_key() :: atom()
  def approved_key, do: @approved_key

  @spec review_summary_key() :: atom()
  def review_summary_key, do: @review_summary_key

  @spec state_key() :: atom()
  def state_key, do: @state_key

  @spec change_proposal_attached_key() :: atom()
  def change_proposal_attached_key, do: @change_proposal_attached_key

  @spec merge_approved_key() :: atom()
  def merge_approved_key, do: @merge_approved_key

  @spec provider_state_open() :: atom()
  def provider_state_open, do: @provider_state_open

  @spec review_summary_approved() :: atom()
  def review_summary_approved, do: @review_summary_approved

  @spec check_summary_passing() :: atom()
  def check_summary_passing, do: @check_summary_passing

  @spec mergeability_summary_mergeable() :: atom()
  def mergeability_summary_mergeable, do: @mergeability_summary_mergeable

  @spec summary_unknown() :: atom()
  def summary_unknown, do: @summary_unknown
end
