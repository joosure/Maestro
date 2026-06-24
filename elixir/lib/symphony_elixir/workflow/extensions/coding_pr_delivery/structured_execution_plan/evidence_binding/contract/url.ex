defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Url do
  @moduledoc """
  URL policy value contract for Coding PR Delivery structured-plan evidence.
  """

  @http_scheme "http"
  @https_scheme "https"
  @compare_path_marker "/compare/"

  @spec allowed_change_proposal_url_schemes() :: [String.t()]
  def allowed_change_proposal_url_schemes, do: [@http_scheme, @https_scheme]

  @spec compare_path_marker() :: String.t()
  def compare_path_marker, do: @compare_path_marker
end
