defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.UrlPolicy do
  @moduledoc """
  URL validity policy for Coding PR Delivery change-proposal evidence.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Url, as: UrlContract

  @spec provider_change_proposal_url?(term()) :: boolean()
  def provider_change_proposal_url?(url) when is_binary(url) do
    uri = URI.parse(url)

    uri.scheme in UrlContract.allowed_change_proposal_url_schemes() and
      is_binary(uri.host) and
      not String.contains?(uri.path || "", UrlContract.compare_path_marker())
  end

  def provider_change_proposal_url?(_url), do: false
end
