defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Labels do
  @moduledoc """
  Presentation labels for workflow structured-plan Workpad rendering.

  These labels are human-facing rendering contract values. They do not define
  canonical plan schema, evidence, or readiness authority.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: WorkflowContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @plan_label "Plan"
  @run_label "Run"
  @issue_label "Issue"
  @tracker_label "Tracker"
  @route_label "Route"
  @status_label "Status"
  @revision_label "Revision"
  @item_status_label "status"
  @item_kind_label "kind"
  @item_owner_label "owner"
  @evidence_label "evidence"
  @none_label "none"
  @empty_items_message "_No structured execution plan items._"
  @truncated_items_message "_Additional items were omitted from this bounded render._"

  @metadata_labels [
    {Fields.plan_id(), @plan_label},
    {Fields.run_id(), @run_label},
    {Fields.issue_id(), @issue_label},
    {Fields.tracker_kind(), @tracker_label},
    {Fields.route_key(), @route_label},
    {Fields.status(), @status_label},
    {Fields.revision(), @revision_label}
  ]

  @spec metadata_labels() :: [{String.t(), String.t()}]
  def metadata_labels, do: @metadata_labels

  @spec section_labels() :: [{String.t(), String.t()}]
  def section_labels, do: WorkflowContract.criticality_display_labels()

  @spec evidence_label() :: String.t()
  def evidence_label, do: @evidence_label

  @spec item_status_label() :: String.t()
  def item_status_label, do: @item_status_label

  @spec item_kind_label() :: String.t()
  def item_kind_label, do: @item_kind_label

  @spec item_owner_label() :: String.t()
  def item_owner_label, do: @item_owner_label

  @spec none_label() :: String.t()
  def none_label, do: @none_label

  @spec empty_items_message() :: String.t()
  def empty_items_message, do: @empty_items_message

  @spec truncated_items_message() :: String.t()
  def truncated_items_message, do: @truncated_items_message
end
