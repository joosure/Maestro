defmodule SymphonyElixir.Workflow.CapabilityNames do
  @moduledoc """
  Canonical workflow capability names used across profiles, providers, tools,
  and readiness checks.

  These values are external protocol strings. Keep them centralized so provider
  adapters and workflow profiles cannot drift when a capability is added,
  renamed, or retired.
  """

  @tracker_issue_read "tracker.issue.read"
  @tracker_issue_update "tracker.issue.update"
  @tracker_issue_create "tracker.issue.create"
  @tracker_comment_read "tracker.comment.read"
  @tracker_comment_write "tracker.comment.write"
  @tracker_comment_update "tracker.comment.update"
  @tracker_state_update "tracker.state.update"
  @tracker_relation_read "tracker.relation.read"
  @tracker_relation_write "tracker.relation.write"
  @tracker_issue_snapshot "tracker.issue_snapshot"
  @tracker_move_issue "tracker.move_issue"
  @tracker_upsert_workpad "tracker.upsert_workpad"
  @tracker_attach_change_proposal "tracker.attach_change_proposal"
  @tracker_upsert_comment "tracker.upsert_comment"
  @tracker_create_follow_up_issue "tracker.create_follow_up_issue"
  @tracker_read_issue_relations "tracker.read_issue_relations"
  @tracker_add_issue_relation "tracker.add_issue_relation"
  @tracker_read_issue_dependencies "tracker.read_issue_dependencies"
  @tracker_save_issue_dependency "tracker.save_issue_dependency"
  @tracker_prepare_file_upload "tracker.prepare_file_upload"
  @tracker_provider_diagnostics "tracker.provider_diagnostics"

  @repo_checkout "repo.checkout"
  @repo_diff "repo.diff"
  @repo_commit "repo.commit"
  @repo_push "repo.push"
  @repo_change_proposal_snapshot "repo.change_proposal_snapshot"
  @repo_create_or_update_change_proposal "repo.create_or_update_change_proposal"
  @repo_read_change_proposal_discussion "repo.read_change_proposal_discussion"
  @repo_add_change_proposal_comment "repo.add_change_proposal_comment"
  @repo_submit_change_proposal_review "repo.submit_change_proposal_review"
  @repo_reply_change_proposal_review_comment "repo.reply_change_proposal_review_comment"
  @repo_read_change_proposal_checks "repo.read_change_proposal_checks"
  @repo_merge_change_proposal "repo.merge_change_proposal"
  @repo_close_change_proposal "repo.close_change_proposal"

  @repo_provider_change_proposal_create "repo_provider.change_proposal.create"
  @repo_provider_change_proposal_read "repo_provider.change_proposal.read"
  @repo_provider_review_read "repo_provider.review.read"
  @repo_provider_review_write "repo_provider.review.write"
  @repo_provider_check_read "repo_provider.check.read"
  @repo_provider_merge "repo_provider.merge"

  @agent_turn_run "agent.turn.run"
  @agent_session_stateful "agent.session.stateful"
  @agent_events_streaming "agent.events.streaming"
  @agent_usage_metrics "agent.usage.metrics"
  @agent_tools_dynamic "agent.tools.dynamic"
  @agent_runtime_remote_worker "agent.runtime.remote_worker"
  @agent_credentials_managed "agent.credentials.managed"
  @agent_quota_probe "agent.quota.probe"

  @spec tracker_issue_read() :: String.t()
  def tracker_issue_read, do: @tracker_issue_read

  @spec tracker_issue_update() :: String.t()
  def tracker_issue_update, do: @tracker_issue_update

  @spec tracker_issue_create() :: String.t()
  def tracker_issue_create, do: @tracker_issue_create

  @spec tracker_comment_read() :: String.t()
  def tracker_comment_read, do: @tracker_comment_read

  @spec tracker_comment_write() :: String.t()
  def tracker_comment_write, do: @tracker_comment_write

  @spec tracker_comment_update() :: String.t()
  def tracker_comment_update, do: @tracker_comment_update

  @spec tracker_state_update() :: String.t()
  def tracker_state_update, do: @tracker_state_update

  @spec tracker_relation_read() :: String.t()
  def tracker_relation_read, do: @tracker_relation_read

  @spec tracker_relation_write() :: String.t()
  def tracker_relation_write, do: @tracker_relation_write

  @spec tracker_issue_snapshot() :: String.t()
  def tracker_issue_snapshot, do: @tracker_issue_snapshot

  @spec tracker_move_issue() :: String.t()
  def tracker_move_issue, do: @tracker_move_issue

  @spec tracker_upsert_workpad() :: String.t()
  def tracker_upsert_workpad, do: @tracker_upsert_workpad

  @spec tracker_attach_change_proposal() :: String.t()
  def tracker_attach_change_proposal, do: @tracker_attach_change_proposal

  @spec tracker_upsert_comment() :: String.t()
  def tracker_upsert_comment, do: @tracker_upsert_comment

  @spec tracker_create_follow_up_issue() :: String.t()
  def tracker_create_follow_up_issue, do: @tracker_create_follow_up_issue

  @spec tracker_read_issue_relations() :: String.t()
  def tracker_read_issue_relations, do: @tracker_read_issue_relations

  @spec tracker_add_issue_relation() :: String.t()
  def tracker_add_issue_relation, do: @tracker_add_issue_relation

  @spec tracker_read_issue_dependencies() :: String.t()
  def tracker_read_issue_dependencies, do: @tracker_read_issue_dependencies

  @spec tracker_save_issue_dependency() :: String.t()
  def tracker_save_issue_dependency, do: @tracker_save_issue_dependency

  @spec tracker_prepare_file_upload() :: String.t()
  def tracker_prepare_file_upload, do: @tracker_prepare_file_upload

  @spec tracker_provider_diagnostics() :: String.t()
  def tracker_provider_diagnostics, do: @tracker_provider_diagnostics

  @spec repo_checkout() :: String.t()
  def repo_checkout, do: @repo_checkout

  @spec repo_diff() :: String.t()
  def repo_diff, do: @repo_diff

  @spec repo_commit() :: String.t()
  def repo_commit, do: @repo_commit

  @spec repo_push() :: String.t()
  def repo_push, do: @repo_push

  @spec repo_change_proposal_snapshot() :: String.t()
  def repo_change_proposal_snapshot, do: @repo_change_proposal_snapshot

  @spec repo_create_or_update_change_proposal() :: String.t()
  def repo_create_or_update_change_proposal, do: @repo_create_or_update_change_proposal

  @spec repo_read_change_proposal_discussion() :: String.t()
  def repo_read_change_proposal_discussion, do: @repo_read_change_proposal_discussion

  @spec repo_add_change_proposal_comment() :: String.t()
  def repo_add_change_proposal_comment, do: @repo_add_change_proposal_comment

  @spec repo_submit_change_proposal_review() :: String.t()
  def repo_submit_change_proposal_review, do: @repo_submit_change_proposal_review

  @spec repo_reply_change_proposal_review_comment() :: String.t()
  def repo_reply_change_proposal_review_comment, do: @repo_reply_change_proposal_review_comment

  @spec repo_read_change_proposal_checks() :: String.t()
  def repo_read_change_proposal_checks, do: @repo_read_change_proposal_checks

  @spec repo_merge_change_proposal() :: String.t()
  def repo_merge_change_proposal, do: @repo_merge_change_proposal

  @spec repo_close_change_proposal() :: String.t()
  def repo_close_change_proposal, do: @repo_close_change_proposal

  @spec repo_provider_change_proposal_create() :: String.t()
  def repo_provider_change_proposal_create, do: @repo_provider_change_proposal_create

  @spec repo_provider_change_proposal_read() :: String.t()
  def repo_provider_change_proposal_read, do: @repo_provider_change_proposal_read

  @spec repo_provider_review_read() :: String.t()
  def repo_provider_review_read, do: @repo_provider_review_read

  @spec repo_provider_review_write() :: String.t()
  def repo_provider_review_write, do: @repo_provider_review_write

  @spec repo_provider_check_read() :: String.t()
  def repo_provider_check_read, do: @repo_provider_check_read

  @spec repo_provider_merge() :: String.t()
  def repo_provider_merge, do: @repo_provider_merge

  @spec agent_turn_run() :: String.t()
  def agent_turn_run, do: @agent_turn_run

  @spec agent_session_stateful() :: String.t()
  def agent_session_stateful, do: @agent_session_stateful

  @spec agent_events_streaming() :: String.t()
  def agent_events_streaming, do: @agent_events_streaming

  @spec agent_usage_metrics() :: String.t()
  def agent_usage_metrics, do: @agent_usage_metrics

  @spec agent_tools_dynamic() :: String.t()
  def agent_tools_dynamic, do: @agent_tools_dynamic

  @spec agent_runtime_remote_worker() :: String.t()
  def agent_runtime_remote_worker, do: @agent_runtime_remote_worker

  @spec agent_credentials_managed() :: String.t()
  def agent_credentials_managed, do: @agent_credentials_managed

  @spec agent_quota_probe() :: String.t()
  def agent_quota_probe, do: @agent_quota_probe

  @spec repo_core() :: [String.t()]
  def repo_core do
    [
      repo_checkout(),
      repo_diff(),
      repo_commit(),
      repo_push()
    ]
  end

  @spec typed_workflow() :: [String.t()]
  def typed_workflow do
    [
      tracker_issue_snapshot(),
      tracker_move_issue(),
      tracker_upsert_workpad(),
      tracker_attach_change_proposal(),
      tracker_upsert_comment(),
      tracker_create_follow_up_issue(),
      tracker_read_issue_relations(),
      tracker_add_issue_relation(),
      tracker_read_issue_dependencies(),
      tracker_save_issue_dependency(),
      tracker_prepare_file_upload(),
      tracker_provider_diagnostics(),
      repo_checkout(),
      repo_diff(),
      repo_commit(),
      repo_push(),
      repo_change_proposal_snapshot(),
      repo_create_or_update_change_proposal(),
      repo_read_change_proposal_discussion(),
      repo_add_change_proposal_comment(),
      repo_submit_change_proposal_review(),
      repo_reply_change_proposal_review_comment(),
      repo_read_change_proposal_checks(),
      repo_merge_change_proposal(),
      repo_close_change_proposal()
    ]
  end

  @spec merge_gate() :: [String.t()]
  def merge_gate do
    [
      repo_provider_merge(),
      repo_merge_change_proposal()
    ]
  end

  @spec merge_gate?(Enumerable.t()) :: boolean()
  def merge_gate?(capabilities) do
    merge_capabilities = MapSet.new(merge_gate())

    capabilities
    |> List.wrap()
    |> Enum.any?(&MapSet.member?(merge_capabilities, &1))
  end
end
