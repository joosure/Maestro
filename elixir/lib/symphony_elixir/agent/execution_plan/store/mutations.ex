defmodule SymphonyElixir.Agent.ExecutionPlan.Store.Mutations do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Evidence
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Item
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Plan
  alias SymphonyElixir.Agent.ExecutionPlan.Schema
  alias SymphonyElixir.Agent.ExecutionPlan.Store.ErrorResults

  @reason_statuses [
    SymphonyElixir.Agent.ExecutionPlan.Contract.blocked_item_status(),
    SymphonyElixir.Agent.ExecutionPlan.Contract.skipped_item_status(),
    SymphonyElixir.Agent.ExecutionPlan.Contract.failed_item_status()
  ]

  @spec prepare_new_plan(Plan.t(), keyword()) :: Plan.t()
  def prepare_new_plan(%Plan{} = plan, opts) do
    if Keyword.get(opts, :preserve_metadata?, false) do
      plan
    else
      timestamp = timestamp(opts)

      %{
        plan
        | revision: 1,
          created_at: timestamp,
          updated_at: timestamp,
          items: Enum.map(plan.items, &prepare_new_item(&1, timestamp))
      }
    end
  end

  @spec prepare_replacement(Plan.t(), Plan.t(), keyword()) :: Plan.t()
  def prepare_replacement(%Plan{} = current_plan, %Plan{} = replacement_plan, opts) do
    if Keyword.get(opts, :preserve_metadata?, false) do
      replacement_plan
    else
      timestamp = timestamp(opts)

      %{
        replacement_plan
        | revision: current_plan.revision + 1,
          created_at: current_plan.created_at,
          updated_at: timestamp,
          items: replacement_items(current_plan.items, replacement_plan.items, timestamp)
      }
    end
  end

  @spec update_plan_status(Plan.t(), String.t(), keyword()) :: Plan.t()
  def update_plan_status(%Plan{} = plan, next_status, opts) do
    plan
    |> bump_plan(opts)
    |> Map.put(:status, next_status)
  end

  @spec update_item_status(Plan.t(), String.t(), String.t(), keyword()) :: Plan.t()
  def update_item_status(%Plan{} = plan, item_id, next_status, opts) do
    item = fetch_item!(plan, item_id)

    updated_item =
      item
      |> bump_item(opts)
      |> Map.put(:status, next_status)
      |> put_status_reason(next_status, opts)

    replace_item(plan, item_id, updated_item, opts)
  end

  @spec append_evidence_ref(Plan.t(), String.t(), map(), keyword()) :: {:ok, Plan.t()} | {:error, map()}
  def append_evidence_ref(%Plan{} = plan, item_id, evidence_ref, opts) do
    item = fetch_item!(plan, item_id)

    case Evidence.append_ref(Record.to_map(item), evidence_ref) do
      {:ok, updated_item_map} ->
        if updated_item_map == Record.to_map(item) do
          {:ok, plan}
        else
          {:ok, replace_item(plan, item_id, updated_item_map |> Item.from_map() |> bump_item(opts), opts)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec upsert_agent_items(Plan.t(), [map()], keyword()) :: {:ok, Plan.t(), [String.t()]} | {:error, map()}
  def upsert_agent_items(%Plan{} = plan, item_maps, opts) do
    original_items = Enum.map(plan.items, &Record.to_map/1)

    with {:ok, {updated_items, item_ids}} <-
           Enum.reduce_while(item_maps, {:ok, {original_items, []}}, fn item, {:ok, {current_items, current_item_ids}} ->
             case upsert_item_map(current_items, item, opts) do
               {:ok, next_items, item_id} -> {:cont, {:ok, {next_items, [item_id | current_item_ids]}}}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end) do
      item_ids = item_ids |> Enum.reverse() |> Enum.filter(&is_binary/1)

      if updated_items == original_items do
        {:ok, plan, item_ids}
      else
        with {:ok, updated_plan} <-
               plan
               |> Record.to_map()
               |> Map.put(Fields.items(), updated_items)
               |> Map.update!(Fields.revision(), &(&1 + 1))
               |> put_updated_at(opts)
               |> Schema.normalize() do
          {:ok, updated_plan, item_ids}
        end
      end
    end
  end

  @spec bump_plan(Plan.t(), keyword()) :: Plan.t()
  def bump_plan(%Plan{} = plan, opts) do
    %{plan | revision: plan.revision + 1, updated_at: timestamp(opts)}
  end

  @spec bump_item(Item.t(), keyword()) :: Item.t()
  def bump_item(%Item{} = item, opts) do
    %{item | revision: item.revision + 1, updated_at: timestamp(opts)}
  end

  defp prepare_new_item(%Item{} = item, timestamp) do
    %{item | revision: 1, created_at: timestamp, updated_at: timestamp}
  end

  defp replacement_items(current_items, replacement_items, timestamp) do
    current_by_id = Map.new(current_items, &{&1.item_id, &1})

    Enum.map(replacement_items, fn item ->
      case Map.get(current_by_id, item.item_id) do
        nil ->
          prepare_new_item(item, timestamp)

        current_item ->
          if Record.to_map(current_item) == Record.to_map(item) do
            current_item
          else
            %{item | created_at: current_item.created_at, updated_at: timestamp, revision: current_item.revision + 1}
          end
      end
    end)
  end

  defp replace_item(%Plan{} = plan, item_id, %Item{} = updated_item, opts) do
    items =
      Enum.map(plan.items, fn item ->
        if item.item_id == item_id, do: updated_item, else: item
      end)

    plan
    |> bump_plan(opts)
    |> Map.put(:items, items)
  end

  defp fetch_item!(%Plan{} = plan, item_id) do
    Enum.find(plan.items, &(&1.item_id == item_id))
  end

  defp put_status_reason(%Item{} = item, status, opts) when status in @reason_statuses do
    %{item | status_reason: Keyword.get(opts, :status_reason)}
  end

  defp put_status_reason(%Item{} = item, _status, _opts), do: %{item | status_reason: nil}

  defp upsert_item_map(items, item, opts) when is_map(item) do
    item_id = Map.get(item, Fields.item_id())

    if is_binary(item_id) do
      case Enum.find_index(items, &(Map.get(&1, Fields.item_id()) == item_id)) do
        nil ->
          {:ok, items ++ [prepare_new_item_map(item, opts)], item_id}

        index ->
          existing_item = Enum.at(items, index)

          updated_item =
            item
            |> Map.put(Fields.created_at(), Map.get(existing_item, Fields.created_at(), Map.get(item, Fields.created_at())))
            |> Map.put(Fields.revision(), Map.get(existing_item, Fields.revision(), 0) + 1)
            |> put_updated_at(opts)

          {:ok, List.replace_at(items, index, updated_item), item_id}
      end
    else
      {:error, ErrorResults.invalid_agent_item(item_id)}
    end
  end

  defp upsert_item_map(_items, item, _opts), do: {:error, ErrorResults.invalid_agent_item(item)}

  defp prepare_new_item_map(item, opts) do
    timestamp = timestamp(opts)

    item
    |> Map.put(Fields.revision(), 1)
    |> Map.put(Fields.created_at(), timestamp)
    |> Map.put(Fields.updated_at(), timestamp)
  end

  defp put_updated_at(record, opts), do: Map.put(record, Fields.updated_at(), timestamp(opts))

  defp timestamp(opts) do
    case Keyword.get(opts, :now) || Keyword.get(opts, :updated_at) do
      timestamp when is_binary(timestamp) -> timestamp
      _timestamp -> DateTime.utc_now(:microsecond) |> DateTime.to_iso8601()
    end
  end
end
