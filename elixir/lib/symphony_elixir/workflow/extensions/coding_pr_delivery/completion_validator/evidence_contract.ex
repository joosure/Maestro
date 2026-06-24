defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceContract do
  @moduledoc """
  Raw evidence input keys and observed-evidence labels for Coding PR Delivery
  completion validation.
  """

  @allowed_completion_routes_key :allowed_completion_routes
  @attachment_key :attachment
  @available_key :available
  @change_proposal_key :change_proposal
  @change_proposal_camel_key :changeProposal
  @change_proposal_attached_key :change_proposal_attached
  @checks_key :checks
  @check_summary_key :check_summary
  @ci_key :ci
  @comment_key :comment
  @comment_written_key :comment_written
  @commit_exists_key :commit_exists
  @commits_key :commits
  @completion_contract_key :completion_contract
  @completion_evidence_key :completion_evidence
  @current_key :current
  @data_key :data
  @diff_key :diff
  @diff_exists_key :diff_exists
  @diff_present_key :diff_present
  @evidence_key :evidence
  @exists_key :exists
  @head_sha_key :head_sha
  @id_key :id
  @items_key :items
  @key_key :key
  @lifecycle_phase_key :lifecycle_phase
  @linked_issue_key :linked_issue
  @linked_issue_camel_key :linkedIssue
  @merge_approved_key :merge_approved
  @missing_key :missing
  @number_key :number
  @passing_key :passing
  @pr_key :pr
  @present_key :present
  @profile_key :profile
  @pull_request_key :pull_request
  @read_key :read
  @recorded_key :recorded
  @repo_key :repo
  @review_key :review
  @reviews_key :reviews
  @review_summary_key :review_summary
  @route_key :route
  @route_key_key :route_key
  @settings_key :settings
  @state_key :state
  @status_key :status
  @summary_key :summary
  @target_key :target
  @target_route_key :target_route
  @tracker_key :tracker
  @tracker_attached_key :tracker_attached
  @tracker_linked_key :tracker_linked
  @url_key :url
  @workflow_key :workflow
  @workpad_upserted_key :workpad_upserted
  @workpad_written_key :workpad_written
  @approved_key :approved
  @checked_key :checked

  @change_proposal_url_label "change_proposal.url"
  @change_proposal_camel_url_label "changeProposal.url"
  @data_change_proposal_camel_url_label "data.changeProposal.url"
  @change_proposal_label "change_proposal"
  @data_attachment_id_label "data.attachment.id"
  @attachment_id_label "attachment.id"
  @tracker_change_proposal_attached_label "tracker.change_proposal_attached"
  @repo_commits_label "repo.commits"
  @repo_diff_present_label "repo.diff_present"
  @repo_head_sha_label "repo.head_sha"
  @checks_passing_label "checks.passing"
  @checks_read_label "checks.read"
  @tracker_workpad_written_label "tracker.workpad_written"
  @review_approved_label "review.approved"
  @merge_capability_available_label "merge_capability.available"
  @tracker_merge_state_label "tracker.merge_state"
  @completion_validator_options_invalid_label "completion_validator.options_invalid"
  @completion_validator_input_invalid_label "completion_validator.input_invalid"
  @route_label_prefix "route="

  @spec allowed_completion_routes_key() :: atom()
  def allowed_completion_routes_key, do: @allowed_completion_routes_key

  @spec attachment_key() :: atom()
  def attachment_key, do: @attachment_key

  @spec available_key() :: atom()
  def available_key, do: @available_key

  @spec change_proposal_key() :: atom()
  def change_proposal_key, do: @change_proposal_key

  @spec change_proposal_camel_key() :: atom()
  def change_proposal_camel_key, do: @change_proposal_camel_key

  @spec change_proposal_attached_key() :: atom()
  def change_proposal_attached_key, do: @change_proposal_attached_key

  @spec checks_key() :: atom()
  def checks_key, do: @checks_key

  @spec check_summary_key() :: atom()
  def check_summary_key, do: @check_summary_key

  @spec ci_key() :: atom()
  def ci_key, do: @ci_key

  @spec comment_key() :: atom()
  def comment_key, do: @comment_key

  @spec comment_written_key() :: atom()
  def comment_written_key, do: @comment_written_key

  @spec commit_exists_key() :: atom()
  def commit_exists_key, do: @commit_exists_key

  @spec commits_key() :: atom()
  def commits_key, do: @commits_key

  @spec completion_contract_key() :: atom()
  def completion_contract_key, do: @completion_contract_key

  @spec completion_evidence_key() :: atom()
  def completion_evidence_key, do: @completion_evidence_key

  @spec current_key() :: atom()
  def current_key, do: @current_key

  @spec data_key() :: atom()
  def data_key, do: @data_key

  @spec diff_key() :: atom()
  def diff_key, do: @diff_key

  @spec diff_exists_key() :: atom()
  def diff_exists_key, do: @diff_exists_key

  @spec diff_present_key() :: atom()
  def diff_present_key, do: @diff_present_key

  @spec evidence_key() :: atom()
  def evidence_key, do: @evidence_key

  @spec exists_key() :: atom()
  def exists_key, do: @exists_key

  @spec head_sha_key() :: atom()
  def head_sha_key, do: @head_sha_key

  @spec id_key() :: atom()
  def id_key, do: @id_key

  @spec items_key() :: atom()
  def items_key, do: @items_key

  @spec key_key() :: atom()
  def key_key, do: @key_key

  @spec lifecycle_phase_key() :: atom()
  def lifecycle_phase_key, do: @lifecycle_phase_key

  @spec linked_issue_key() :: atom()
  def linked_issue_key, do: @linked_issue_key

  @spec linked_issue_camel_key() :: atom()
  def linked_issue_camel_key, do: @linked_issue_camel_key

  @spec merge_approved_key() :: atom()
  def merge_approved_key, do: @merge_approved_key

  @spec missing_key() :: atom()
  def missing_key, do: @missing_key

  @spec number_key() :: atom()
  def number_key, do: @number_key

  @spec passing_key() :: atom()
  def passing_key, do: @passing_key

  @spec pr_key() :: atom()
  def pr_key, do: @pr_key

  @spec present_key() :: atom()
  def present_key, do: @present_key

  @spec profile_key() :: atom()
  def profile_key, do: @profile_key

  @spec pull_request_key() :: atom()
  def pull_request_key, do: @pull_request_key

  @spec read_key() :: atom()
  def read_key, do: @read_key

  @spec recorded_key() :: atom()
  def recorded_key, do: @recorded_key

  @spec repo_key() :: atom()
  def repo_key, do: @repo_key

  @spec review_key() :: atom()
  def review_key, do: @review_key

  @spec reviews_key() :: atom()
  def reviews_key, do: @reviews_key

  @spec review_summary_key() :: atom()
  def review_summary_key, do: @review_summary_key

  @spec route_key() :: atom()
  def route_key, do: @route_key

  @spec route_key_key() :: atom()
  def route_key_key, do: @route_key_key

  @spec settings_key() :: atom()
  def settings_key, do: @settings_key

  @spec state_key() :: atom()
  def state_key, do: @state_key

  @spec status_key() :: atom()
  def status_key, do: @status_key

  @spec summary_key() :: atom()
  def summary_key, do: @summary_key

  @spec target_key() :: atom()
  def target_key, do: @target_key

  @spec target_route_key() :: atom()
  def target_route_key, do: @target_route_key

  @spec tracker_key() :: atom()
  def tracker_key, do: @tracker_key

  @spec tracker_attached_key() :: atom()
  def tracker_attached_key, do: @tracker_attached_key

  @spec tracker_linked_key() :: atom()
  def tracker_linked_key, do: @tracker_linked_key

  @spec url_key() :: atom()
  def url_key, do: @url_key

  @spec workflow_key() :: atom()
  def workflow_key, do: @workflow_key

  @spec workpad_upserted_key() :: atom()
  def workpad_upserted_key, do: @workpad_upserted_key

  @spec workpad_written_key() :: atom()
  def workpad_written_key, do: @workpad_written_key

  @spec approved_key() :: atom()
  def approved_key, do: @approved_key

  @spec checked_key() :: atom()
  def checked_key, do: @checked_key

  @spec change_proposal_url_label() :: String.t()
  def change_proposal_url_label, do: @change_proposal_url_label

  @spec change_proposal_camel_url_label() :: String.t()
  def change_proposal_camel_url_label, do: @change_proposal_camel_url_label

  @spec data_change_proposal_camel_url_label() :: String.t()
  def data_change_proposal_camel_url_label, do: @data_change_proposal_camel_url_label

  @spec change_proposal_label() :: String.t()
  def change_proposal_label, do: @change_proposal_label

  @spec data_attachment_id_label() :: String.t()
  def data_attachment_id_label, do: @data_attachment_id_label

  @spec attachment_id_label() :: String.t()
  def attachment_id_label, do: @attachment_id_label

  @spec tracker_change_proposal_attached_label() :: String.t()
  def tracker_change_proposal_attached_label, do: @tracker_change_proposal_attached_label

  @spec repo_commits_label() :: String.t()
  def repo_commits_label, do: @repo_commits_label

  @spec repo_diff_present_label() :: String.t()
  def repo_diff_present_label, do: @repo_diff_present_label

  @spec repo_head_sha_label() :: String.t()
  def repo_head_sha_label, do: @repo_head_sha_label

  @spec checks_passing_label() :: String.t()
  def checks_passing_label, do: @checks_passing_label

  @spec checks_read_label() :: String.t()
  def checks_read_label, do: @checks_read_label

  @spec tracker_workpad_written_label() :: String.t()
  def tracker_workpad_written_label, do: @tracker_workpad_written_label

  @spec review_approved_label() :: String.t()
  def review_approved_label, do: @review_approved_label

  @spec merge_capability_available_label() :: String.t()
  def merge_capability_available_label, do: @merge_capability_available_label

  @spec tracker_merge_state_label() :: String.t()
  def tracker_merge_state_label, do: @tracker_merge_state_label

  @spec completion_validator_options_invalid_label() :: String.t()
  def completion_validator_options_invalid_label, do: @completion_validator_options_invalid_label

  @spec completion_validator_input_invalid_label() :: String.t()
  def completion_validator_input_invalid_label, do: @completion_validator_input_invalid_label

  @spec route_label(String.t()) :: String.t()
  def route_label(route_key), do: @route_label_prefix <> route_key
end
