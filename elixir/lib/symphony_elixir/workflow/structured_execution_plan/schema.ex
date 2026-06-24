defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Schema do
  @moduledoc """
  Facade for canonical `workflow.execution_plan.v1` schema validation.

  Focused submodules own plan envelope, profile, item, requirement, and shared
  validation concerns. This module remains the stable public entrypoint.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Plan

  @spec validate(map()) :: {:ok, map()} | {:error, map()}
  def validate(plan), do: Plan.validate(plan)
end
