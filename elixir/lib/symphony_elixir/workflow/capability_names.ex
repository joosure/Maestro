defmodule SymphonyElixir.Workflow.CapabilityNames do
  @moduledoc """
  Workflow-owned capability strings.

  Provider and agent capability strings are owned by their domains and
  contributed through `SymphonyElixir.Capability.Registry`. This module keeps
  only workflow-plan capability strings local to the Workflow context.
  """

  @behaviour SymphonyElixir.Capability.Source

  @workflow_plan_snapshot "workflow.plan_snapshot"
  @workflow_plan_upsert "workflow.plan_upsert"
  @workflow_plan_update_item "workflow.plan_update_item"
  @workflow_plan_render_workpad "workflow.plan_render_workpad"

  @spec workflow_plan_snapshot() :: String.t()
  def workflow_plan_snapshot, do: @workflow_plan_snapshot

  @spec workflow_plan_upsert() :: String.t()
  def workflow_plan_upsert, do: @workflow_plan_upsert

  @spec workflow_plan_update_item() :: String.t()
  def workflow_plan_update_item, do: @workflow_plan_update_item

  @spec workflow_plan_render_workpad() :: String.t()
  def workflow_plan_render_workpad, do: @workflow_plan_render_workpad

  @impl true
  def capabilities, do: workflow_plan_capabilities()

  @impl true
  def typed_tool_capabilities, do: workflow_plan_capabilities()

  @spec workflow_plan_capabilities() :: [String.t()]
  def workflow_plan_capabilities do
    [
      workflow_plan_snapshot(),
      workflow_plan_upsert(),
      workflow_plan_update_item(),
      workflow_plan_render_workpad()
    ]
  end
end
