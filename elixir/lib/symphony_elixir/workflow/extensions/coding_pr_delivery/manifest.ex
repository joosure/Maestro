defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Manifest do
  @moduledoc """
  Static manifest projection for the bundled Coding PR Delivery extension.

  External plugin packages should provide the same metadata through their own
  release manifest or registry source. The extension facade consumes this
  projection instead of owning package metadata itself.
  """

  @extension_id "symphony.workflow.extension.coding_pr_delivery"
  @extension_version "builtin.v1"

  @spec id() :: String.t()
  def id, do: @extension_id

  @spec version() :: String.t()
  def version, do: @extension_version
end
