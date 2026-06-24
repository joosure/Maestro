defmodule SymphonyElixir.Agent.ExecutionPlan.StatusMachine do
  @moduledoc """
  Provider-neutral status transition table for canonical execution plans.

  Workflow adoption layers may add domain statuses as extension transitions, but
  generic Agent plans do not know workflow-specific states such as handoff
  readiness.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.StatusMachine.TransitionTable

  @spec allowed_plan_transition?(term(), term()) :: boolean()
  def allowed_plan_transition?(from_status, to_status) do
    TransitionTable.allowed?(Contract.plan_status_transitions(), from_status, to_status)
  end

  @spec allowed_item_transition?(term(), term()) :: boolean()
  def allowed_item_transition?(from_status, to_status) do
    TransitionTable.allowed?(Contract.item_status_transitions(), from_status, to_status)
  end

  @spec validate_plan_transition(term(), term()) :: :ok | {:error, map()}
  def validate_plan_transition(from_status, to_status) do
    TransitionTable.validate(Contract.plan_status_transitions(), &Contract.plan_status?/1, from_status, to_status, :plan)
  end

  @spec validate_item_transition(term(), term()) :: :ok | {:error, map()}
  def validate_item_transition(from_status, to_status) do
    TransitionTable.validate(Contract.item_status_transitions(), &Contract.item_status?/1, from_status, to_status, :item)
  end
end
