defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Fields do
  @moduledoc false

  @component :component
  @tracker_kind :tracker_kind
  @issue_id :issue_id
  @issue_identifier :issue_identifier
  @running_count :running_count
  @claimed_count :claimed_count
  @available_slots :available_slots
  @max_concurrent_agents :max_concurrent_agents

  @workflow_profile_kind :workflow_profile_kind
  @workflow_profile_version :workflow_profile_version

  @source_route_refs :source_route_refs
  @source_states :source_states
  @source_state :source_state
  @source_workflow_profile :source_workflow_profile
  @source_workflow_profile_version :source_workflow_profile_version
  @source_workflow_route_key :source_workflow_route_key

  @target_workflow_profile :target_workflow_profile
  @target_workflow_profile_version :target_workflow_profile_version
  @target_workflow_route_key :target_workflow_route_key

  @repo_provider_kind :repo_provider_kind
  @repository :repository
  @change_proposal_number :change_proposal_number
  @change_proposal_url :change_proposal_url
  @change_proposal_branch :change_proposal_branch
  @head_sha :head_sha
  @provider_state :provider_state
  @review_summary :review_summary
  @check_summary :check_summary
  @mergeability_summary :mergeability_summary
  @retryable :retryable
  @error :error

  @decision :decision
  @reason :reason
  @skip_reason :skip_reason
  @lookup_failure_reason :lookup_failure_reason
  @target_state :target_state
  @previous_state :previous_state

  @route_ref_profile "workflow_profile"
  @route_ref_profile_version "workflow_profile_version"
  @route_ref_route_key "workflow_route_key"

  @spec component() :: atom()
  def component, do: @component

  @spec tracker_kind() :: atom()
  def tracker_kind, do: @tracker_kind

  @spec issue_id() :: atom()
  def issue_id, do: @issue_id

  @spec issue_identifier() :: atom()
  def issue_identifier, do: @issue_identifier

  @spec running_count() :: atom()
  def running_count, do: @running_count

  @spec claimed_count() :: atom()
  def claimed_count, do: @claimed_count

  @spec available_slots() :: atom()
  def available_slots, do: @available_slots

  @spec max_concurrent_agents() :: atom()
  def max_concurrent_agents, do: @max_concurrent_agents

  @spec workflow_profile_kind() :: atom()
  def workflow_profile_kind, do: @workflow_profile_kind

  @spec workflow_profile_version() :: atom()
  def workflow_profile_version, do: @workflow_profile_version

  @spec source_route_refs() :: atom()
  def source_route_refs, do: @source_route_refs

  @spec source_states() :: atom()
  def source_states, do: @source_states

  @spec source_state() :: atom()
  def source_state, do: @source_state

  @spec source_workflow_profile() :: atom()
  def source_workflow_profile, do: @source_workflow_profile

  @spec source_workflow_profile_version() :: atom()
  def source_workflow_profile_version, do: @source_workflow_profile_version

  @spec source_workflow_route_key() :: atom()
  def source_workflow_route_key, do: @source_workflow_route_key

  @spec target_workflow_profile() :: atom()
  def target_workflow_profile, do: @target_workflow_profile

  @spec target_workflow_profile_version() :: atom()
  def target_workflow_profile_version, do: @target_workflow_profile_version

  @spec target_workflow_route_key() :: atom()
  def target_workflow_route_key, do: @target_workflow_route_key

  @spec repo_provider_kind() :: atom()
  def repo_provider_kind, do: @repo_provider_kind

  @spec repository() :: atom()
  def repository, do: @repository

  @spec change_proposal_number() :: atom()
  def change_proposal_number, do: @change_proposal_number

  @spec change_proposal_url() :: atom()
  def change_proposal_url, do: @change_proposal_url

  @spec change_proposal_branch() :: atom()
  def change_proposal_branch, do: @change_proposal_branch

  @spec head_sha() :: atom()
  def head_sha, do: @head_sha

  @spec provider_state() :: atom()
  def provider_state, do: @provider_state

  @spec review_summary() :: atom()
  def review_summary, do: @review_summary

  @spec check_summary() :: atom()
  def check_summary, do: @check_summary

  @spec mergeability_summary() :: atom()
  def mergeability_summary, do: @mergeability_summary

  @spec retryable() :: atom()
  def retryable, do: @retryable

  @spec error() :: atom()
  def error, do: @error

  @spec decision() :: atom()
  def decision, do: @decision

  @spec reason() :: atom()
  def reason, do: @reason

  @spec skip_reason() :: atom()
  def skip_reason, do: @skip_reason

  @spec lookup_failure_reason() :: atom()
  def lookup_failure_reason, do: @lookup_failure_reason

  @spec target_state() :: atom()
  def target_state, do: @target_state

  @spec previous_state() :: atom()
  def previous_state, do: @previous_state

  @spec route_ref_profile() :: String.t()
  def route_ref_profile, do: @route_ref_profile

  @spec route_ref_profile_version() :: String.t()
  def route_ref_profile_version, do: @route_ref_profile_version

  @spec route_ref_route_key() :: String.t()
  def route_ref_route_key, do: @route_ref_route_key
end
