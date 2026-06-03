defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Evidence do
  @moduledoc """
  Stable observation bucket and field keys used by readiness policies.
  """

  @workpad_key "workpad"
  @repo_key "repo"
  @change_proposal_key "change_proposal"
  @validation_key "validation"
  @checks_key "checks"
  @feedback_key "feedback"

  @status_key "status"
  @source_key "source"
  @key_key "key"
  @id_key "id"
  @url_key "url"
  @head_ref_key "head_ref"
  @head_sha_key "head_sha"
  @published_head_sha_key "published_head_sha"
  @commits_key "commits"
  @change_kind_key "change_kind"
  @no_code_change_justification_key "no_code_change_justification"
  @linked_to_tracker_key "linked_to_tracker"
  @observed_at_key "observed_at"
  @commands_key "commands"
  @workpad_id_key "workpad_id"
  @updated_at_key "updated_at"
  @provider_kind_key "provider_kind"
  @repository_key "repository"
  @number_key "number"
  @summary_key "summary"
  @actionable_count_key "actionable_count"
  @working_tree_clean_key "working_tree_clean"
  @pushed_key "pushed"
  @command_key "command"
  @cwd_key "cwd"
  @exit_code_key "exit_code"

  @spec workpad_key() :: String.t()
  def workpad_key, do: @workpad_key

  @spec repo_key() :: String.t()
  def repo_key, do: @repo_key

  @spec change_proposal_key() :: String.t()
  def change_proposal_key, do: @change_proposal_key

  @spec validation_key() :: String.t()
  def validation_key, do: @validation_key

  @spec checks_key() :: String.t()
  def checks_key, do: @checks_key

  @spec feedback_key() :: String.t()
  def feedback_key, do: @feedback_key

  @spec status_key() :: String.t()
  def status_key, do: @status_key

  @spec source_key() :: String.t()
  def source_key, do: @source_key

  @spec key_key() :: String.t()
  def key_key, do: @key_key

  @spec id_key() :: String.t()
  def id_key, do: @id_key

  @spec url_key() :: String.t()
  def url_key, do: @url_key

  @spec head_ref_key() :: String.t()
  def head_ref_key, do: @head_ref_key

  @spec head_sha_key() :: String.t()
  def head_sha_key, do: @head_sha_key

  @spec published_head_sha_key() :: String.t()
  def published_head_sha_key, do: @published_head_sha_key

  @spec commits_key() :: String.t()
  def commits_key, do: @commits_key

  @spec change_kind_key() :: String.t()
  def change_kind_key, do: @change_kind_key

  @spec no_code_change_justification_key() :: String.t()
  def no_code_change_justification_key, do: @no_code_change_justification_key

  @spec linked_to_tracker_key() :: String.t()
  def linked_to_tracker_key, do: @linked_to_tracker_key

  @spec observed_at_key() :: String.t()
  def observed_at_key, do: @observed_at_key

  @spec commands_key() :: String.t()
  def commands_key, do: @commands_key

  @spec workpad_id_key() :: String.t()
  def workpad_id_key, do: @workpad_id_key

  @spec updated_at_key() :: String.t()
  def updated_at_key, do: @updated_at_key

  @spec provider_kind_key() :: String.t()
  def provider_kind_key, do: @provider_kind_key

  @spec repository_key() :: String.t()
  def repository_key, do: @repository_key

  @spec number_key() :: String.t()
  def number_key, do: @number_key

  @spec summary_key() :: String.t()
  def summary_key, do: @summary_key

  @spec actionable_count_key() :: String.t()
  def actionable_count_key, do: @actionable_count_key

  @spec working_tree_clean_key() :: String.t()
  def working_tree_clean_key, do: @working_tree_clean_key

  @spec pushed_key() :: String.t()
  def pushed_key, do: @pushed_key

  @spec command_key() :: String.t()
  def command_key, do: @command_key

  @spec cwd_key() :: String.t()
  def cwd_key, do: @cwd_key

  @spec exit_code_key() :: String.t()
  def exit_code_key, do: @exit_code_key
end
