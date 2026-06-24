defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine do
  @moduledoc """
  Workflow adoption status transitions for structured execution plan records.

  Generic plan and item transitions are owned by the Agent execution-plan
  contract. The workflow adoption contract adds workflow-specific extension
  transitions such as `handoff_ready`; this status machine consumes the merged
  workflow contract table without keeping private transition literals.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.StatusMachine.TransitionTable
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract

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
