defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.StatusMachine do
  @moduledoc """
  Agent execution-plan status-machine machine-code contract.
  """

  @plan_status_transition_forbidden "plan_status_transition_forbidden"
  @item_status_transition_forbidden "item_status_transition_forbidden"

  @spec plan_status_transition_forbidden() :: String.t()
  def plan_status_transition_forbidden, do: @plan_status_transition_forbidden

  @spec item_status_transition_forbidden() :: String.t()
  def item_status_transition_forbidden, do: @item_status_transition_forbidden
end
