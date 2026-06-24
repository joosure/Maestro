defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.ErrorCodes do
  @moduledoc """
  Workflow structured-plan schema machine-code contract.

  Generic validation and item/evidence duplicate codes stay owned by
  `SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.*`; this module owns only
  workflow-envelope-specific schema codes.
  """

  @invalid_route_ref "invalid_route_ref"

  @spec invalid_route_ref() :: String.t()
  def invalid_route_ref, do: @invalid_route_ref
end
