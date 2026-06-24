defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Store do
  @moduledoc """
  Agent execution-plan store machine-code contract.
  """

  @plan_conflict "plan_conflict"
  @plan_not_found "plan_not_found"
  @plan_id_mismatch "plan_id_mismatch"
  @revision_conflict "revision_conflict"
  @item_update_not_allowed "item_update_not_allowed"
  @item_not_found "item_not_found"
  @store_unavailable "store_unavailable"

  @spec plan_conflict() :: String.t()
  def plan_conflict, do: @plan_conflict

  @spec plan_not_found() :: String.t()
  def plan_not_found, do: @plan_not_found

  @spec plan_id_mismatch() :: String.t()
  def plan_id_mismatch, do: @plan_id_mismatch

  @spec revision_conflict() :: String.t()
  def revision_conflict, do: @revision_conflict

  @spec item_update_not_allowed() :: String.t()
  def item_update_not_allowed, do: @item_update_not_allowed

  @spec item_not_found() :: String.t()
  def item_not_found, do: @item_not_found

  @spec store_unavailable() :: String.t()
  def store_unavailable, do: @store_unavailable
end
