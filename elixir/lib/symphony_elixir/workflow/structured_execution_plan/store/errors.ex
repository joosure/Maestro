defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Errors do
  @moduledoc """
  Workflow structured-plan store error payload builders.

  `Store.ErrorCodes` owns stable machine codes. This module owns the public
  error payload shapes returned by the workflow Store facade and persistence boundary.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes

  @spec plan_not_found(String.t() | nil) :: map()
  def plan_not_found(nil) do
    %{code: ErrorCodes.plan_not_found(), message: "Structured execution plan was not found."}
  end

  def plan_not_found(plan_id) do
    %{code: ErrorCodes.plan_not_found(), message: "Structured execution plan was not found.", plan_id: plan_id}
  end

  @spec item_not_found(String.t()) :: map()
  def item_not_found(item_id) when is_binary(item_id) do
    %{
      code: ErrorCodes.item_not_found(),
      message: "Structured execution plan item was not found.",
      item_id: item_id
    }
  end

  @spec invalid_route_ref(term()) :: map()
  def invalid_route_ref(reason) do
    %{code: ErrorCodes.invalid_route_ref(), message: "Structured execution plan route reference is invalid.", reason: inspect(reason)}
  end

  @spec service_unavailable() :: map()
  def service_unavailable do
    %{code: ErrorCodes.store_unavailable(), message: "Structured execution plan store is not running."}
  end
end
