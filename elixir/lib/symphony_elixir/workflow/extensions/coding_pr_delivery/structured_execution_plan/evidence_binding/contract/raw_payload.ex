defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.RawPayload do
  @moduledoc """
  Raw typed-tool payload key contract for Coding PR Delivery evidence binding.
  """

  @data_key "data"
  @change_proposal_key "changeProposal"
  @checks_key "checks"
  @discussion_key "discussion"
  @attachment_key "attachment"
  @summary_key "summary"
  @actionable_feedback_count_key "actionableFeedbackCount"
  @actionable_items_key "actionableItems"
  @provider_key "provider"
  @repository_key "repository"
  @id_key "id"
  @number_key "number"
  @target_key "target"
  @url_key "url"
  @head_ref_name_key "headRefName"
  @head_ref_key "head_ref"
  @branch_key "branch"
  @head_ref_oid_key "headRefOid"
  @head_sha_camel_key "headSha"
  @head_sha_key "head_sha"
  @action_key "action"
  @exists_key "exists"
  @kind_key "kind"
  @provider_kind_key "provider_kind"

  @spec data_key() :: String.t()
  def data_key, do: @data_key

  @spec change_proposal_key() :: String.t()
  def change_proposal_key, do: @change_proposal_key

  @spec checks_key() :: String.t()
  def checks_key, do: @checks_key

  @spec discussion_key() :: String.t()
  def discussion_key, do: @discussion_key

  @spec attachment_key() :: String.t()
  def attachment_key, do: @attachment_key

  @spec summary_key() :: String.t()
  def summary_key, do: @summary_key

  @spec actionable_feedback_count_key() :: String.t()
  def actionable_feedback_count_key, do: @actionable_feedback_count_key

  @spec actionable_items_key() :: String.t()
  def actionable_items_key, do: @actionable_items_key

  @spec provider_key() :: String.t()
  def provider_key, do: @provider_key

  @spec repository_key() :: String.t()
  def repository_key, do: @repository_key

  @spec id_key() :: String.t()
  def id_key, do: @id_key

  @spec number_key() :: String.t()
  def number_key, do: @number_key

  @spec target_key() :: String.t()
  def target_key, do: @target_key

  @spec url_key() :: String.t()
  def url_key, do: @url_key

  @spec head_ref_name_key() :: String.t()
  def head_ref_name_key, do: @head_ref_name_key

  @spec head_ref_key() :: String.t()
  def head_ref_key, do: @head_ref_key

  @spec branch_key() :: String.t()
  def branch_key, do: @branch_key

  @spec head_ref_oid_key() :: String.t()
  def head_ref_oid_key, do: @head_ref_oid_key

  @spec head_sha_camel_key() :: String.t()
  def head_sha_camel_key, do: @head_sha_camel_key

  @spec head_sha_key() :: String.t()
  def head_sha_key, do: @head_sha_key

  @spec action_key() :: String.t()
  def action_key, do: @action_key

  @spec exists_key() :: String.t()
  def exists_key, do: @exists_key

  @spec kind_key() :: String.t()
  def kind_key, do: @kind_key

  @spec provider_kind_key() :: String.t()
  def provider_kind_key, do: @provider_kind_key
end
