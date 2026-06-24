defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Values do
  @moduledoc """
  Value aliases used by Coding PR Delivery completion validation.
  """

  alias SymphonyElixir.RepoProvider.Capabilities, as: RepoProviderCapabilities

  @passing_check_statuses ["passing", "passed", "success", "successful"]
  @approved_review_statuses ["approved", "approval", "passed"]
  @truthy_strings ["true", "yes", "passed", "passing"]
  @merge_route_key "merging"

  @spec merge_capabilities() :: MapSet.t(String.t())
  def merge_capabilities, do: MapSet.new(RepoProviderCapabilities.merge_gate_capabilities())

  @spec passing_check_statuses() :: [String.t()]
  def passing_check_statuses, do: @passing_check_statuses

  @spec approved_review_statuses() :: [String.t()]
  def approved_review_statuses, do: @approved_review_statuses

  @spec truthy_strings() :: [String.t()]
  def truthy_strings, do: @truthy_strings

  @spec merge_route_key() :: String.t()
  def merge_route_key, do: @merge_route_key
end
