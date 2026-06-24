defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Payload do
  @moduledoc """
  Normalized structured-plan evidence payload key contract for Coding PR Delivery.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceContract, as: Evidence

  @provider_kind_key "provider_kind"
  @repository_key "repository"
  @id_key "id"
  @number_key "number"
  @head_ref_key "head_ref"
  @action_key "action"
  @exists_key "exists"
  @run_count_key "run_count"
  @actionable_count_key "actionable_count"
  @checks_status_key "checks_status"
  @checks_head_sha_key "checks_head_sha"
  @discussion_status_key "discussion_status"
  @discussion_actionable_count_key "discussion_actionable_count"
  @tracker_kind_key "tracker_kind"
  @attachment_id_key "attachment_id"
  @change_proposal_id_key "change_proposal_id"
  @repo_provider_kind_key "repo_provider_kind"

  @spec provider_kind_key() :: String.t()
  def provider_kind_key, do: @provider_kind_key

  @spec repository_key() :: String.t()
  def repository_key, do: @repository_key

  @spec id_key() :: String.t()
  def id_key, do: @id_key

  @spec number_key() :: String.t()
  def number_key, do: @number_key

  @spec url_key() :: String.t()
  def url_key, do: Evidence.url_key()

  @spec head_ref_key() :: String.t()
  def head_ref_key, do: @head_ref_key

  @spec head_sha_key() :: String.t()
  def head_sha_key, do: Evidence.head_sha_key()

  @spec action_key() :: String.t()
  def action_key, do: @action_key

  @spec exists_key() :: String.t()
  def exists_key, do: @exists_key

  @spec status_key() :: String.t()
  def status_key, do: Evidence.status_key()

  @spec run_count_key() :: String.t()
  def run_count_key, do: @run_count_key

  @spec actionable_count_key() :: String.t()
  def actionable_count_key, do: @actionable_count_key

  @spec checks_status_key() :: String.t()
  def checks_status_key, do: @checks_status_key

  @spec checks_head_sha_key() :: String.t()
  def checks_head_sha_key, do: @checks_head_sha_key

  @spec discussion_status_key() :: String.t()
  def discussion_status_key, do: @discussion_status_key

  @spec discussion_actionable_count_key() :: String.t()
  def discussion_actionable_count_key, do: @discussion_actionable_count_key

  @spec tracker_kind_key() :: String.t()
  def tracker_kind_key, do: @tracker_kind_key

  @spec attachment_id_key() :: String.t()
  def attachment_id_key, do: @attachment_id_key

  @spec change_proposal_id_key() :: String.t()
  def change_proposal_id_key, do: @change_proposal_id_key

  @spec repo_provider_kind_key() :: String.t()
  def repo_provider_kind_key, do: @repo_provider_kind_key

  @spec linked_to_tracker_key() :: String.t()
  def linked_to_tracker_key, do: Evidence.linked_to_tracker_key()
end
