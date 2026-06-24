defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.ErrorCodes do
  @moduledoc """
  Workflow structured-plan typed-tool machine-code contract.

  Generic tool and store codes are delegated to their owning contracts. This
  module owns only workflow structured-plan tool-specific codes.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Tool, as: AgentToolErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes, as: StoreErrorCodes

  @missing_required_evidence "missing_required_evidence"
  @tool_failed "structured_plan_tool_failed"

  @spec invalid_arguments() :: String.t()
  defdelegate invalid_arguments, to: AgentToolErrorCodes

  @spec unsupported_tool() :: String.t()
  defdelegate unsupported_tool, to: AgentToolErrorCodes

  @spec revision_conflict() :: String.t()
  defdelegate revision_conflict, to: StoreErrorCodes

  @spec item_not_found() :: String.t()
  defdelegate item_not_found, to: StoreErrorCodes

  @spec missing_required_evidence() :: String.t()
  def missing_required_evidence, do: @missing_required_evidence

  @spec tool_failed() :: String.t()
  def tool_failed, do: @tool_failed
end
