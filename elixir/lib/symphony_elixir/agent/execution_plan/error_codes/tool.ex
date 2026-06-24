defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Tool do
  @moduledoc """
  Agent execution-plan typed-tool machine-code contract.
  """

  @invalid_arguments "invalid_arguments"
  @unsupported_tool "unsupported_tool"
  @tool_failed "agent_execution_plan_tool_failed"

  @spec invalid_arguments() :: String.t()
  def invalid_arguments, do: @invalid_arguments

  @spec unsupported_tool() :: String.t()
  def unsupported_tool, do: @unsupported_tool

  @spec tool_failed() :: String.t()
  def tool_failed, do: @tool_failed
end
