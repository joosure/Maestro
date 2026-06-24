defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ErrorCodes do
  @moduledoc """
  Machine-code contract for workflow structured-plan evidence binding.
  """

  @missing_run_id "missing_run_id"
  @missing_issue_id "missing_issue_id"

  @spec missing_run_id() :: String.t()
  def missing_run_id, do: @missing_run_id

  @spec missing_issue_id() :: String.t()
  def missing_issue_id, do: @missing_issue_id
end
