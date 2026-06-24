defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Status do
  @moduledoc """
  Local status value contract for Coding PR Delivery structured-plan evidence.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  @action_required_status "action_required"

  @spec discussion_action_required_status() :: String.t()
  def discussion_action_required_status, do: @action_required_status

  @spec discussion_clear_status() :: String.t()
  def discussion_clear_status, do: Values.clear_status()
end
