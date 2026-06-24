defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Projection do
  @moduledoc """
  Projection identifiers used when workflow plans are mapped to Agent plans.

  These values are workflow adoption metadata. They must not move into the
  generic Agent execution-plan contract.
  """

  @plan_extension_key "symphony.workflow.execution_plan"
  @item_extension_key "symphony.workflow.execution_plan.item"
  @evidence_extension_key "symphony.workflow.execution_plan.evidence"

  @workflow_context_kind "workflow_run"
  @workflow_context_source "workflow"
  @execution_context_mode "execution"
  @workflow_ref_profile_key "profile"
  @workflow_workspace_id_separator ":"

  @spec plan_extension_key() :: String.t()
  def plan_extension_key, do: @plan_extension_key

  @spec item_extension_key() :: String.t()
  def item_extension_key, do: @item_extension_key

  @spec evidence_extension_key() :: String.t()
  def evidence_extension_key, do: @evidence_extension_key

  @spec workflow_context_kind() :: String.t()
  def workflow_context_kind, do: @workflow_context_kind

  @spec workflow_context_source() :: String.t()
  def workflow_context_source, do: @workflow_context_source

  @spec execution_context_mode() :: String.t()
  def execution_context_mode, do: @execution_context_mode

  @spec workflow_ref_profile_key() :: String.t()
  def workflow_ref_profile_key, do: @workflow_ref_profile_key

  @spec workflow_workspace_id_separator() :: String.t()
  def workflow_workspace_id_separator, do: @workflow_workspace_id_separator
end
