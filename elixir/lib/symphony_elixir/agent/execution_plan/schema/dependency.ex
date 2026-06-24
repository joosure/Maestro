defmodule SymphonyElixir.Agent.ExecutionPlan.Schema.Dependency do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Schema, as: SchemaErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  import SymphonyElixir.Agent.ExecutionPlan.Schema.Validation, only: [non_empty_string?: 1]

  @spec errors([term()]) :: [map()]
  def errors(items), do: duplicate_item_id_errors(items) ++ dependency_errors(items)

  defp duplicate_item_id_errors(items) do
    item_ids =
      items
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, Fields.item_id()))
      |> Enum.filter(&non_empty_string?/1)

    item_ids
    |> Enum.frequencies()
    |> Enum.filter(fn {_item_id, count} -> count > 1 end)
    |> Enum.map(fn {item_id, _count} ->
      %{
        code: SchemaErrorCodes.duplicate_item_id(),
        path: [Fields.items()],
        message: "Plan item ids must be unique.",
        item_id: item_id
      }
    end)
  end

  defp dependency_errors(items) do
    item_ids =
      items
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, Fields.item_id()))
      |> Enum.filter(&non_empty_string?/1)

    item_id_set = MapSet.new(item_ids)
    unknown_dependency_errors = unknown_dependency_errors(items, item_id_set)

    unknown_dependency_errors ++ dependency_cycle_errors(items, item_id_set)
  end

  defp unknown_dependency_errors(items, item_id_set) do
    items
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(fn item ->
      item_id = Map.get(item, Fields.item_id())

      case Map.get(item, Fields.depends_on()) do
        dependencies when is_list(dependencies) ->
          dependencies
          |> Enum.filter(&is_binary/1)
          |> Enum.reject(&MapSet.member?(item_id_set, &1))
          |> Enum.map(fn dependency_id ->
            %{
              code: SchemaErrorCodes.invalid_dependency(),
              path: [Fields.items()],
              message: "Plan item dependency must refer to an item in the same plan.",
              item_id: item_id,
              dependency_id: dependency_id
            }
          end)

        _dependencies ->
          []
      end
    end)
  end

  defp dependency_cycle_errors(items, item_id_set) do
    graph =
      items
      |> Enum.filter(&is_map/1)
      |> Enum.reduce(%{}, fn item, graph ->
        item_id = Map.get(item, Fields.item_id())
        dependencies = Map.get(item, Fields.depends_on(), [])

        if non_empty_string?(item_id) and is_list(dependencies) do
          Map.put(graph, item_id, Enum.filter(dependencies, &MapSet.member?(item_id_set, &1)))
        else
          graph
        end
      end)

    if dependency_cycle?(graph) do
      [
        %{
          code: SchemaErrorCodes.dependency_cycle(),
          path: [Fields.items()],
          message: "Plan item dependencies must not contain cycles."
        }
      ]
    else
      []
    end
  end

  defp dependency_cycle?(graph) do
    result =
      graph
      |> Map.keys()
      |> Enum.reduce_while({MapSet.new(), MapSet.new()}, fn item_id, {visited, stack} ->
        case visit_dependency_node(item_id, graph, visited, stack) do
          {:cycle, visited, stack} -> {:halt, {:cycle, visited, stack}}
          {:ok, visited, stack} -> {:cont, {visited, stack}}
        end
      end)

    match?({:cycle, _visited, _stack}, result)
  end

  defp visit_dependency_node(item_id, graph, visited, stack) do
    cond do
      MapSet.member?(stack, item_id) ->
        {:cycle, visited, stack}

      MapSet.member?(visited, item_id) ->
        {:ok, visited, stack}

      true ->
        visited = MapSet.put(visited, item_id)
        stack = MapSet.put(stack, item_id)

        graph
        |> Map.get(item_id, [])
        |> Enum.reduce_while({:ok, visited, stack}, fn dependency_id, {:ok, visited, stack} ->
          case visit_dependency_node(dependency_id, graph, visited, stack) do
            {:ok, visited, stack} -> {:cont, {:ok, visited, stack}}
            {:cycle, visited, stack} -> {:halt, {:cycle, visited, stack}}
          end
        end)
        |> case do
          {:ok, visited, stack} -> {:ok, visited, MapSet.delete(stack, item_id)}
          {:cycle, visited, stack} -> {:cycle, visited, stack}
        end
    end
  end
end
