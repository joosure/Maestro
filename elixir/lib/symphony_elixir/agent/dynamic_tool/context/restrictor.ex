defmodule SymphonyElixir.Agent.DynamicTool.Context.Restrictor do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource
  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.{Conflict, Entry}
  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.Context, as: CompositeContext
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Context.Normalizer
  alias SymphonyElixir.Agent.DynamicTool.ToolSpec

  @spec restrict_tools(Context.t(), [String.t()]) :: Context.t() | term()
  def restrict_tools(%Context{} = context, tool_names) when is_list(tool_names) do
    allowed_names =
      tool_names
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    tool_specs = context |> Map.get(:tool_specs, []) |> filter_tool_specs(allowed_names)
    tool_metadata = context |> Map.get(:tool_metadata, %{}) |> Map.take(MapSet.to_list(allowed_names))

    context
    |> Map.put(:tool_specs, tool_specs)
    |> Map.put(:tool_metadata, tool_metadata)
    |> Map.put(:source_context, restrict_source_context(context.source, context.source_context, allowed_names))
  end

  def restrict_tools(context, tool_names) when is_map(context) and is_list(tool_names) do
    context
    |> Normalizer.normalize()
    |> restrict_tools(tool_names)
  end

  def restrict_tools(context, _tool_names), do: context

  defp filter_tool_specs(tool_specs, allowed_names) when is_list(tool_specs) do
    Enum.filter(tool_specs, fn tool_spec ->
      case tool_name(tool_spec) do
        name when is_binary(name) -> MapSet.member?(allowed_names, name)
        _name -> false
      end
    end)
  end

  defp restrict_source_context(CompositeSource, source_context, allowed_names) do
    source_context
    |> CompositeContext.normalize()
    |> restrict_composite_context(allowed_names)
  end

  defp restrict_source_context(_source, source_context, _allowed_names), do: source_context

  defp restrict_composite_context(%CompositeContext{} = source_context, allowed_names) do
    %CompositeContext{
      source_context
      | tool_specs: filter_tool_specs(source_context.tool_specs, allowed_names),
        routes: Map.take(source_context.routes, MapSet.to_list(allowed_names)),
        sources: restrict_entries(source_context.sources, allowed_names),
        conflicts: restrict_conflicts(source_context.conflicts, allowed_names)
    }
  end

  defp restrict_entries(entries, allowed_names) when is_list(entries) do
    Enum.map(entries, fn
      %Entry{} = entry ->
        %Entry{entry | tool_specs: filter_tool_specs(entry.tool_specs, allowed_names)}

      entry ->
        entry
    end)
  end

  defp restrict_conflicts(conflicts, allowed_names) when is_list(conflicts) do
    Enum.filter(conflicts, fn
      %Conflict{tool: tool} when is_binary(tool) -> MapSet.member?(allowed_names, tool)
      _conflict -> false
    end)
  end

  defp tool_name(%ToolSpec{name: name}) when is_binary(name), do: name

  defp tool_name(tool_spec) when is_map(tool_spec) do
    case Map.get(tool_spec, ToolSpec.name_key()) do
      name when is_binary(name) -> name
      _name -> nil
    end
  end

  defp tool_name(_tool_spec), do: nil
end
