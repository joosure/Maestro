defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ChangeProposalUrl do
  @moduledoc """
  URL classification helpers for Coding PR Delivery change proposals.
  """

  @http_schemes ~w(http https)
  @path_markers ["/pull/", "/pulls/", "/merge_requests/", "/-/merge_requests/"]

  @spec change_proposal_url?(term()) :: boolean()
  def change_proposal_url?(url) when is_binary(url) do
    absolute_http_url?(url) and Enum.any?(@path_markers, &String.contains?(url, &1))
  end

  def change_proposal_url?(_url), do: false

  defp absolute_http_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in @http_schemes and is_binary(host) -> true
      _uri -> false
    end
  end
end
