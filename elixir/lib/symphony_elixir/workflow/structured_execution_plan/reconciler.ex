defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler do
  @moduledoc """
  Recomputes structured execution plan item status from immutable evidence refs.

  This module is the orchestration facade. Field keys, status values, evidence
  kinds, requirement matching, freshness, and evidence-specific policy live in
  focused contract/policy modules so reconciliation consumes only canonical
  execution-plan records.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.Freshness
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.Requirements
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine

  @spec reconcile(map()) :: {:ok, map()} | {:error, map()}
  def reconcile(plan) when is_map(plan) do
    items = Map.get(plan, AgentFields.items(), [])

    if is_list(items) do
      {:ok, Map.put(plan, AgentFields.items(), Enum.map(items, &reconcile_item(&1, items)))}
    else
      {:error, schema_invalid_error("Structured execution plan items must be an array.")}
    end
  end

  def reconcile(_plan), do: {:error, schema_invalid_error("Structured execution plan must be an object.")}

  @spec satisfied?(map()) :: boolean()
  def satisfied?(item) when is_map(item), do: Requirements.satisfied?(item)
  def satisfied?(_item), do: false

  defp reconcile_item(item, all_items) when is_map(item) do
    cond do
      Contract.terminal_item_status?(Map.get(item, AgentFields.status())) ->
        item

      Freshness.stale?(item, all_items) ->
        maybe_put_status(item, AgentContract.in_progress_item_status())

      Requirements.satisfied?(item) ->
        maybe_put_status(item, AgentContract.complete_item_status())

      true ->
        item
    end
  end

  defp reconcile_item(item, _all_items), do: item

  defp maybe_put_status(item, status) when is_map(item) do
    from_status = Map.get(item, AgentFields.status())

    cond do
      from_status == status ->
        item

      StatusMachine.allowed_item_transition?(from_status, status) ->
        Map.put(item, AgentFields.status(), status)

      true ->
        item
    end
  end

  defp schema_invalid_error(message), do: %{code: ValidationErrorCodes.schema_invalid(), message: message}
end
