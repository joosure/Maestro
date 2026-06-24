defmodule SymphonyElixir.Agent.DynamicTool.Context.Query do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Context.Normalizer
  alias SymphonyElixir.Agent.DynamicTool.Context.RuntimeMetadata
  alias SymphonyElixir.Agent.DynamicTool.Context.ToolPlan
  alias SymphonyElixir.Agent.DynamicTool.{Metadata, Source, ToolSpec}

  @spec source(Context.t()) :: module()
  def source(%Context{source: source}), do: Normalizer.normalize_source(source, [])
  def source(context) when is_map(context), do: context |> Normalizer.normalize() |> source()
  def source(_context), do: Source.default()

  @spec source_context(Context.t()) :: term()
  def source_context(%Context{source: source, source_context: source_context}),
    do: source |> Normalizer.normalize_source([]) |> Normalizer.normalize_source_context(source_context)

  def source_context(context) when is_map(context), do: context |> Normalizer.normalize() |> source_context()

  def source_context(_context), do: Source.default_context(Source.default(), [])

  @spec source_kind(Context.t()) :: String.t() | nil
  def source_kind(%Context{source_kind: source_kind}) when is_binary(source_kind), do: source_kind

  def source_kind(context) when is_map(context) do
    source = source(context)
    Source.kind(source, source_context(context))
  end

  def source_kind(_context), do: nil

  @spec tool_specs(Context.t()) :: [map()]
  def tool_specs(%Context{tool_specs: tool_specs}) when is_list(tool_specs) do
    ToolSpec.to_maps(tool_specs)
  end

  def tool_specs(context) when is_map(context), do: context |> Normalizer.normalize() |> tool_specs()
  def tool_specs(_context), do: []

  @spec tool_spec(Context.t(), String.t()) :: map() | nil
  def tool_spec(context, name) when is_binary(name) do
    context
    |> tool_spec_record(name)
    |> case do
      %ToolSpec{} = tool_spec -> ToolSpec.to_map(tool_spec)
      nil -> nil
    end
  end

  @spec tool_spec_record(Context.t(), String.t()) :: ToolSpec.t() | nil
  def tool_spec_record(%Context{tool_specs: tool_specs}, name) when is_list(tool_specs) and is_binary(name) do
    Enum.find(tool_specs, &(tool_name(&1) == name))
    |> normalize_tool_spec_record()
  end

  def tool_spec_record(context, name) when is_map(context) and is_binary(name),
    do: context |> Normalizer.normalize() |> tool_spec_record(name)

  def tool_spec_record(_context, _name), do: nil

  @spec tool_enabled?(Context.t(), String.t()) :: boolean()
  def tool_enabled?(context, name) when is_binary(name), do: not is_nil(tool_spec(context, name))

  @spec tool_metadata(Context.t()) :: map()
  def tool_metadata(%Context{tool_metadata: tool_metadata}) when is_map(tool_metadata),
    do: Metadata.to_map_by_tool(tool_metadata)

  def tool_metadata(context) when is_map(context), do: context |> Normalizer.normalize() |> tool_metadata()
  def tool_metadata(_context), do: %{}

  @spec metadata_for(Context.t(), String.t()) :: Metadata.t()
  def metadata_for(%Context{tool_metadata: tool_metadata}, tool) when is_map(tool_metadata) and is_binary(tool) do
    tool_metadata
    |> Map.get(tool, Metadata.default())
    |> Metadata.normalize()
  end

  def metadata_for(context, tool) when is_map(context) and is_binary(tool),
    do: context |> Normalizer.normalize() |> metadata_for(tool)

  def metadata_for(_context, _tool), do: Metadata.default()

  @spec tool_plan_exposure(Context.t()) :: String.t() | nil
  def tool_plan_exposure(%Context{tool_plan: %ToolPlan{} = tool_plan}), do: ToolPlan.exposure(tool_plan)
  def tool_plan_exposure(%Context{}), do: nil

  def tool_plan_exposure(context) when is_map(context),
    do: context |> Normalizer.normalize() |> tool_plan_exposure()

  def tool_plan_exposure(_context), do: nil

  @spec runtime_metadata(Context.t()) :: RuntimeMetadata.t()
  def runtime_metadata(%Context{runtime_metadata: runtime_metadata}) when is_map(runtime_metadata) do
    case RuntimeMetadata.normalize(runtime_metadata) do
      {:ok, runtime_metadata} -> runtime_metadata
      :error -> RuntimeMetadata.empty()
    end
  end

  def runtime_metadata(context) when is_map(context),
    do: context |> Normalizer.normalize() |> runtime_metadata()

  def runtime_metadata(_context), do: RuntimeMetadata.empty()

  @spec runtime_metadata_value(Context.t(), atom() | String.t()) :: term()
  def runtime_metadata_value(context, field), do: context |> runtime_metadata() |> RuntimeMetadata.value(field)

  defp normalize_tool_spec_record(nil), do: nil
  defp normalize_tool_spec_record(%ToolSpec{} = tool_spec), do: tool_spec

  defp normalize_tool_spec_record(tool_spec) do
    case ToolSpec.normalize(tool_spec) do
      {:ok, record} -> record
      :error -> nil
    end
  end

  defp tool_name(%ToolSpec{name: name}) when is_binary(name), do: name

  defp tool_name(_tool_spec), do: nil
end
