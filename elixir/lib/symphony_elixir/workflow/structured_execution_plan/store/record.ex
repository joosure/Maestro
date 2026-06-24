defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Record do
  @moduledoc """
  Canonical workflow-store record mutation helpers.

  The store facade owns transaction orchestration. This module owns common
  immutable record updates so revision and timestamp changes stay consistent
  across item, evidence, and provider-session event paths.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @spec bump_plan(map(), keyword()) :: map()
  def bump_plan(plan, opts) when is_map(plan) and is_list(opts) do
    plan
    |> Map.update!(Fields.revision(), &(&1 + 1))
    |> maybe_put_updated_at(opts)
  end

  @spec bump_item(map(), keyword()) :: map()
  def bump_item(item, opts) when is_map(item) and is_list(opts) do
    item
    |> Map.update!(AgentFields.revision(), &(&1 + 1))
    |> maybe_put_updated_at(opts)
  end

  @spec put_items(map(), [map()], keyword()) :: map()
  def put_items(plan, items, opts) when is_map(plan) and is_list(items) and is_list(opts) do
    plan
    |> bump_plan(opts)
    |> Map.put(Fields.items(), items)
  end

  @spec update_item(map(), String.t(), map(), keyword()) :: map()
  def update_item(plan, item_id, updated_item, opts)
      when is_map(plan) and is_binary(item_id) and is_map(updated_item) and is_list(opts) do
    items =
      Enum.map(Map.fetch!(plan, Fields.items()), fn item ->
        if Map.get(item, AgentFields.item_id()) == item_id, do: updated_item, else: item
      end)

    put_items(plan, items, opts)
  end

  @spec maybe_put_updated_at(map(), keyword()) :: map()
  def maybe_put_updated_at(record, opts) when is_map(record) and is_list(opts) do
    case Keyword.get(opts, :updated_at) do
      timestamp when is_binary(timestamp) -> Map.put(record, AgentFields.updated_at(), timestamp)
      _timestamp -> record
    end
  end
end
