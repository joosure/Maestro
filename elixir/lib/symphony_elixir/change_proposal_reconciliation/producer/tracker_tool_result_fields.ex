defmodule SymphonyElixir.ChangeProposalReconciliation.Producer.TrackerToolResultFields do
  @moduledoc false

  @spec tool_metadata() :: String.t()
  def tool_metadata, do: "tool_metadata"

  @spec tool_plan() :: String.t()
  def tool_plan, do: "tool_plan"

  @spec tool() :: String.t()
  def tool, do: "tool"

  @spec name() :: String.t()
  def name, do: "name"

  @spec workflow_capability() :: String.t()
  def workflow_capability, do: "workflowCapability"

  @spec workflow_capability_snake() :: String.t()
  def workflow_capability_snake, do: "workflow_capability"

  @spec exposure() :: String.t()
  def exposure, do: "exposure"

  @spec diagnostics_exposure() :: String.t()
  def diagnostics_exposure, do: "diagnostics"
end
