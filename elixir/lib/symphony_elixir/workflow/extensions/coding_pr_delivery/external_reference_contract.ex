defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ExternalReferenceContract do
  @moduledoc """
  Coding PR Delivery interpretation contract for tracker external references.

  Tracker sources expose generic external-reference attachment tools. This
  contract names the fields that the Coding PR Delivery extension uses when it
  chooses to interpret one of those generic references as a change proposal.
  """

  @reference_kind_key "reference_kind"
  @change_proposal_kind "change_proposal"
  @provider_kind_key "provider_kind"
  @external_id_key "external_id"
  @metadata_key "metadata"
  @external_reference_key "externalReference"
  @external_reference_snake_key "external_reference"
  @external_id_camel_key "externalId"

  @spec reference_kind_key() :: String.t()
  def reference_kind_key, do: @reference_kind_key

  @spec change_proposal_kind() :: String.t()
  def change_proposal_kind, do: @change_proposal_kind

  @spec provider_kind_key() :: String.t()
  def provider_kind_key, do: @provider_kind_key

  @spec external_id_key() :: String.t()
  def external_id_key, do: @external_id_key

  @spec metadata_key() :: String.t()
  def metadata_key, do: @metadata_key

  @spec external_reference_key() :: String.t()
  def external_reference_key, do: @external_reference_key

  @spec external_reference_snake_key() :: String.t()
  def external_reference_snake_key, do: @external_reference_snake_key

  @spec external_id_camel_key() :: String.t()
  def external_id_camel_key, do: @external_id_camel_key
end
