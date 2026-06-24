defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ResourceIdentityContract do
  @moduledoc """
  Resource identity vocabulary for Coding PR Delivery retry-policy grouping.
  """

  @change_proposal_resource_kind "change_proposal"
  @pr_url_key "pr_url"
  @pull_request_url_key "pull_request_url"
  @url_key "url"
  @reference_kind_atom_key :reference_kind
  @external_id_atom_key :external_id
  @url_atom_key :url

  @spec change_proposal_resource_kind() :: String.t()
  def change_proposal_resource_kind, do: @change_proposal_resource_kind

  @spec pr_url_key() :: String.t()
  def pr_url_key, do: @pr_url_key

  @spec pr_url_atom_key() :: atom()
  def pr_url_atom_key, do: :pr_url

  @spec pull_request_url_key() :: String.t()
  def pull_request_url_key, do: @pull_request_url_key

  @spec pull_request_url_atom_key() :: atom()
  def pull_request_url_atom_key, do: :pull_request_url

  @spec url_key() :: String.t()
  def url_key, do: @url_key

  @spec reference_kind_atom_key() :: atom()
  def reference_kind_atom_key, do: @reference_kind_atom_key

  @spec external_id_atom_key() :: atom()
  def external_id_atom_key, do: @external_id_atom_key

  @spec url_atom_key() :: atom()
  def url_atom_key, do: @url_atom_key
end
