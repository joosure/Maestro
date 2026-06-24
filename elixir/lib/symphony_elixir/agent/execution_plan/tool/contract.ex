defmodule SymphonyElixir.Agent.ExecutionPlan.Tool.Contract do
  @moduledoc """
  Stable contract for generic Agent execution-plan Dynamic Tools.

  This module owns canonical Agent execution-plan tool names, argument keys,
  result keys, side-effect metadata, risk flags, and capability strings. Dynamic
  Tool spec construction lives in `SymphonyElixir.Agent.ExecutionPlan.Tool.Specs`.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: ExecutionPlanContract
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Specs

  @snapshot_tool "agent_execution_plan_snapshot"
  @upsert_tool "agent_execution_plan_upsert"
  @update_item_tool "agent_execution_plan_update_item"
  @append_evidence_tool "agent_execution_plan_append_evidence"
  @write_risk_flag "agent_execution_plan_write"

  @plan_arg "plan"
  @plan_revision_arg "plan_revision"
  @evidence_ref_arg "evidence_ref"

  @success_key "success"
  @plan_key "plan"
  @changed_items_key "changed_items"
  @errors_key "errors"
  @warnings_key "warnings"
  @item_count_key "item_count"
  @items_truncated_key "items_truncated"
  @evidence_ref_count_key "evidence_ref_count"
  @evidence_kinds_key "evidence_kinds"
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

  @spec append_evidence_tool() :: String.t()
  def append_evidence_tool, do: @append_evidence_tool

  @spec tools() :: [String.t()]
  def tools, do: [@snapshot_tool, @upsert_tool, @update_item_tool, @append_evidence_tool]

  @spec source_kind() :: String.t()
  def source_kind, do: ExecutionPlanContract.agent_owner()

  @spec write_risk_flag() :: String.t()
  def write_risk_flag, do: @write_risk_flag

  @spec write_risk_flags() :: [String.t()]
  def write_risk_flags, do: [@write_risk_flag]

  @spec snapshot_capability() :: String.t()
  def snapshot_capability, do: ExecutionPlanContract.snapshot_capability()

  @spec upsert_capability() :: String.t()
  def upsert_capability, do: ExecutionPlanContract.upsert_capability()

  @spec update_item_capability() :: String.t()
  def update_item_capability, do: ExecutionPlanContract.update_item_capability()

  @spec append_evidence_capability() :: String.t()
  def append_evidence_capability, do: ExecutionPlanContract.append_evidence_capability()

  @spec plan_arg() :: String.t()
  def plan_arg, do: @plan_arg

  @spec plan_revision_arg() :: String.t()
  def plan_revision_arg, do: @plan_revision_arg

  @spec evidence_ref_arg() :: String.t()
  def evidence_ref_arg, do: @evidence_ref_arg

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
