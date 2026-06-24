defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.ErrorCodes do
  @moduledoc """
  Stable machine codes for workflow structured-plan adoption initialization.
  """

  @missing_context "structured_plan_adoption_missing_context"
  @profile_resolution_failed "structured_plan_adoption_profile_resolution_failed"
  @invalid_adoption_module "structured_plan_adoption_invalid_module"

  @spec missing_context() :: String.t()
  def missing_context, do: @missing_context

  @spec profile_resolution_failed() :: String.t()
  def profile_resolution_failed, do: @profile_resolution_failed

  @spec invalid_adoption_module() :: String.t()
  def invalid_adoption_module, do: @invalid_adoption_module
end
