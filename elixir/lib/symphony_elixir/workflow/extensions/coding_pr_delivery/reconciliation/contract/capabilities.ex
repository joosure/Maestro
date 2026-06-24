defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Capabilities do
  @moduledoc false

  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities

  @tracker_attach_external_reference_capability TrackerCapabilities.attach_external_reference()
  @tracker_move_issue_capability TrackerCapabilities.move_issue()

  @spec tracker_attach_external_reference_capability() :: String.t()
  def tracker_attach_external_reference_capability, do: @tracker_attach_external_reference_capability

  @spec tracker_move_issue_capability() :: String.t()
  def tracker_move_issue_capability, do: @tracker_move_issue_capability
end
