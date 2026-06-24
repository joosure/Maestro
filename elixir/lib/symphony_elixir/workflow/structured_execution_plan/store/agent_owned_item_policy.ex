defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.AgentOwnedItemPolicy do
  @moduledoc """
  Store policy for agent-owned item upserts.

  Agent tools may draft their own informational items. They cannot replace
  profile-owned/backend-owned items or manufacture critical handoff authority.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Record

  @spec ensure_upsertable_items([map()]) :: :ok | {:error, map()}
  def ensure_upsertable_items(items) when is_list(items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case ensure_upsertable_item(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec upsert(map(), [map()], keyword()) :: {:ok, map()} | {:error, map()}
  def upsert(plan, items, opts) when is_map(plan) and is_list(items) and is_list(opts) do
    original_items = Map.fetch!(plan, Fields.items())

    with {:ok, updated_items} <-
           Enum.reduce_while(items, {:ok, original_items}, fn item, {:ok, current_items} ->
             case upsert_item(current_items, item, opts) do
               {:ok, next_items} -> {:cont, {:ok, next_items}}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end) do
      if updated_items == original_items do
        {:ok, plan}
      else
        {:ok, Record.put_items(plan, updated_items, opts)}
      end
    end
  end

  @spec agent_owned_item?(map()) :: boolean()
  def agent_owned_item?(item) when is_map(item) do
    Map.get(item, AgentFields.owned_by()) == Contract.agent_owner() and
      Map.get(item, AgentFields.source()) == Contract.agent_source() and
      Map.get(item, AgentFields.required()) == false and
      Map.get(item, AgentFields.criticality()) == Contract.informational_criticality()
  end

  defp ensure_upsertable_item(item) when is_map(item) do
    case Map.fetch(item, AgentFields.item_id()) do
      {:ok, item_id} when is_binary(item_id) ->
        ensure_upsertable_item(item, item_id)

      _missing_or_invalid ->
        {:error,
         %{
           code: ErrorCodes.schema_invalid(),
           message: "Agent item upsert requires item objects with item_id."
         }}
    end
  end

  defp ensure_upsertable_item(_item) do
    {:error,
     %{
       code: ErrorCodes.schema_invalid(),
       message: "Agent item upsert requires item objects with item_id."
     }}
  end

  defp ensure_upsertable_item(item, item_id) do
    cond do
      Map.get(item, AgentFields.owned_by()) != Contract.agent_owner() ->
        {:error, rejected(item_id, "Agent plan tools can only upsert agent-owned items.")}

      Map.get(item, AgentFields.source()) != Contract.agent_source() ->
        {:error, rejected(item_id, "Agent plan tools can only upsert agent-sourced items.")}

      Map.get(item, AgentFields.required()) != false ->
        {:error, rejected(item_id, "Agent plan tools cannot create required items.")}

      Map.get(item, AgentFields.criticality()) != Contract.informational_criticality() ->
        {:error, rejected(item_id, "Agent plan tools cannot create critical items.")}

      Map.get(item, AgentFields.evidence_requirements()) not in [nil, []] ->
        {:error, rejected(item_id, "Agent plan tools cannot create evidence-bound items.")}

      Map.get(item, AgentFields.evidence_refs()) not in [nil, []] ->
        {:error, rejected(item_id, "Agent plan tools cannot attach evidence through item upsert.")}

      true ->
        :ok
    end
  end

  defp upsert_item(items, item, opts) do
    item_id = Map.fetch!(item, AgentFields.item_id())

    case Enum.find_index(items, &(Map.get(&1, AgentFields.item_id()) == item_id)) do
      nil ->
        {:ok, items ++ [item]}

      index ->
        existing_item = Enum.at(items, index)

        if agent_owned_item?(existing_item) do
          updated_item =
            item
            |> Map.put(AgentFields.created_at(), Map.get(existing_item, AgentFields.created_at(), Map.get(item, AgentFields.created_at())))
            |> Map.put(AgentFields.revision(), Map.get(existing_item, AgentFields.revision(), 0) + 1)
            |> Record.maybe_put_updated_at(opts)

          {:ok, List.replace_at(items, index, updated_item)}
        else
          {:error, rejected(item_id, "Agent plan tools cannot replace profile-owned or backend-owned items.")}
        end
    end
  end

  defp rejected(item_id, message) do
    %{
      code: ErrorCodes.item_update_not_allowed(),
      message: message,
      item_id: item_id
    }
  end
end
