defmodule SymphonyElixir.Agent.ExecutionPlan.Tool.Guards do
  @moduledoc """
  Guard helpers for generic Agent execution-plan tool commands.

  These helpers operate on canonical Agent plan snapshots and parsed command
  structs. They do not parse raw Dynamic Tool input.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Store.ErrorResults
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Command.UpdateItem

  @items_key Fields.items()

  @spec ensure_agent_owned_update(map(), UpdateItem.t()) :: :ok | {:error, map()}
  def ensure_agent_owned_update(plan, %UpdateItem{item_id: item_id, status: status}) do
    with {:ok, item} <- fetch_item(plan, item_id) do
      cond do
        Map.get(item, Fields.owned_by()) != Contract.agent_owner() ->
          {:error, ErrorResults.item_update_not_allowed(item_id, "Agent execution plan tools can only update agent-owned items.")}

        status == Contract.complete_item_status() and Contract.evidence_required_criticality?(Map.get(item, Fields.criticality())) ->
          {:error, ErrorResults.item_update_not_allowed(item_id, "Agent execution plan tools cannot complete critical or policy-required items.")}

        true ->
          :ok
      end
    end
  end

  @spec fetch_item(map(), String.t()) :: {:ok, map()} | {:error, map()}
  def fetch_item(%{@items_key => items}, item_id) when is_list(items) do
    case Enum.find(items, &(Map.get(&1, Fields.item_id()) == item_id)) do
      nil -> {:error, ErrorResults.item_not_found(item_id)}
      item -> {:ok, item}
    end
  end

  def fetch_item(_plan, item_id), do: {:error, ErrorResults.item_not_found(item_id)}
end
