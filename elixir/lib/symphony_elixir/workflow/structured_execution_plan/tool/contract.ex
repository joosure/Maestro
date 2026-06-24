defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Contract do
  @moduledoc """
  Stable contract for workflow structured execution-plan Dynamic Tools.

  This module owns canonical workflow plan tool names, argument keys, result
  keys, side-effect metadata, risk flags, and mode values. Dynamic Tool spec
  construction lives in `SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Specs`.
  Provider-facing aliases remain a Dynamic Tool source boundary concern and
  must map back to these canonical names before execution.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Specs

  @snapshot_tool "workflow_plan_snapshot"
  @upsert_tool "workflow_plan_upsert"
  @update_item_tool "workflow_plan_update_item"
  @render_workpad_tool "workflow_plan_render_workpad"

  @source_kind "workflow"
  @write_risk_flag "workflow_state_write"

  @plan_arg "plan"
  @plan_revision_arg "plan_revision"
  @mode_arg "mode"
  @heading_arg "heading"
  @max_items_arg "max_items"
  @note_arg "note"
  @evidence_id_arg AgentFields.evidence_id()
  @preview_mode "preview"

  @success_key "success"
  @plan_key "plan"
  @changed_items_key "changed_items"
  @errors_key "errors"
  @warnings_key "warnings"
  @item_count_key "item_count"
  @items_truncated_key "items_truncated"
  @evidence_ref_count_key "evidence_ref_count"
  @evidence_kinds_key "evidence_kinds"
  @rendered_workpad_key "rendered_workpad"
  @data_key "data"
  @error_key "error"
  @code_key "code"
  @message_key "message"
  @details_key "details"
  @reason_key "reason"

  @spec snapshot_tool() :: String.t()
  def snapshot_tool, do: @snapshot_tool

  @spec upsert_tool() :: String.t()
  def upsert_tool, do: @upsert_tool

  @spec update_item_tool() :: String.t()
  def update_item_tool, do: @update_item_tool

  @spec render_workpad_tool() :: String.t()
  def render_workpad_tool, do: @render_workpad_tool

  @spec tools() :: [String.t()]
  def tools, do: [@snapshot_tool, @upsert_tool, @update_item_tool, @render_workpad_tool]

  @spec source_kind() :: String.t()
  def source_kind, do: @source_kind

  @spec write_risk_flag() :: String.t()
  def write_risk_flag, do: @write_risk_flag

  @spec write_risk_flags() :: [String.t()]
  def write_risk_flags, do: [@write_risk_flag]

  @spec plan_arg() :: String.t()
  def plan_arg, do: @plan_arg

  @spec plan_revision_arg() :: String.t()
  def plan_revision_arg, do: @plan_revision_arg

  @spec mode_arg() :: String.t()
  def mode_arg, do: @mode_arg

  @spec heading_arg() :: String.t()
  def heading_arg, do: @heading_arg

  @spec max_items_arg() :: String.t()
  def max_items_arg, do: @max_items_arg

  @spec note_arg() :: String.t()
  def note_arg, do: @note_arg

  @spec evidence_id_arg() :: String.t()
  def evidence_id_arg, do: @evidence_id_arg

  @spec preview_mode() :: String.t()
  def preview_mode, do: @preview_mode

  @spec success_key() :: String.t()
  def success_key, do: @success_key

  @spec plan_key() :: String.t()
  def plan_key, do: @plan_key

  @spec changed_items_key() :: String.t()
  def changed_items_key, do: @changed_items_key

  @spec errors_key() :: String.t()
  def errors_key, do: @errors_key

  @spec warnings_key() :: String.t()
  def warnings_key, do: @warnings_key

  @spec item_count_key() :: String.t()
  def item_count_key, do: @item_count_key

  @spec items_truncated_key() :: String.t()
  def items_truncated_key, do: @items_truncated_key

  @spec evidence_ref_count_key() :: String.t()
  def evidence_ref_count_key, do: @evidence_ref_count_key

  @spec evidence_kinds_key() :: String.t()
  def evidence_kinds_key, do: @evidence_kinds_key

  @spec rendered_workpad_key() :: String.t()
  def rendered_workpad_key, do: @rendered_workpad_key

  @spec data_key() :: String.t()
  def data_key, do: @data_key

  @spec error_key() :: String.t()
  def error_key, do: @error_key

  @spec code_key() :: String.t()
  def code_key, do: @code_key

  @spec message_key() :: String.t()
  def message_key, do: @message_key

  @spec details_key() :: String.t()
  def details_key, do: @details_key

  @spec reason_key() :: String.t()
  def reason_key, do: @reason_key

  @spec tool_specs() :: [map()]
  defdelegate tool_specs, to: Specs
end
