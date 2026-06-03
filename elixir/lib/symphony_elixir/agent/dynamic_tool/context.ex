defmodule SymphonyElixir.Agent.DynamicTool.Context do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.{Policy, Source, Spec}

  @type t :: %{
          optional(:runtime_metadata) => map(),
          optional(:workflow_settings) => map(),
          source: module(),
          source_context: term(),
          source_kind: String.t() | nil,
          tool_specs: [map()],
          tool_metadata: map(),
          tool_environment: map()
        }

  @empty_source Module.concat(["SymphonyElixir", "Agent", "DynamicTool", "CompositeSource"])

  @spec empty() :: t()
  def empty do
    %{
      source: @empty_source,
      source_context: %{sources: [], tool_specs: [], routes: %{}},
      source_kind: "composite",
      tool_specs: [],
      tool_metadata: %{},
      tool_environment: %{},
      runtime_metadata: %{},
      workflow_settings: %{}
    }
  end

  @spec capture(keyword()) :: t()
  def capture(opts \\ []) when is_list(opts) do
    source = Source.from_opts(opts)
    source_context = Keyword.get_lazy(opts, :dynamic_tool_source_context, fn -> Source.default_context(source, opts) end)
    tool_specs = Source.tools(source, source_context, opts)

    %{
      source: source,
      source_context: source_context,
      source_kind: Source.kind(source, source_context),
      tool_specs: Spec.normalize_many(tool_specs),
      tool_metadata: Policy.metadata_many(tool_specs),
      tool_environment: Source.environment(source, source_context, opts)
    }
    |> put_workflow_settings(opts)
  end

  @spec from_opts(keyword()) :: t()
  def from_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :tool_context) do
      %{tool_specs: tool_specs} = context when is_list(tool_specs) ->
        normalize_context(context, opts)

      _context ->
        capture(opts)
    end
  end

  @spec source(t()) :: module()
  def source(%{source: source}) when is_atom(source), do: source
  def source(_context), do: Source.default()

  @spec source_context(t()) :: term()
  def source_context(%{source_context: source_context}), do: source_context
  def source_context(_context), do: Source.default_context(Source.default(), [])

  @spec source_kind(t()) :: String.t() | nil
  def source_kind(%{source_kind: source_kind}) when is_binary(source_kind), do: source_kind

  def source_kind(context) when is_map(context) do
    source = source(context)
    Source.kind(source, source_context(context))
  end

  def source_kind(_context), do: nil

  @spec tool_specs(t()) :: [map()]
  def tool_specs(%{tool_specs: tool_specs}) when is_list(tool_specs), do: Spec.normalize_many(tool_specs)
  def tool_specs(_context), do: []

  @spec tool_spec(t(), String.t()) :: map() | nil
  def tool_spec(context, name) when is_binary(name) do
    Enum.find(tool_specs(context), fn
      %{"name" => ^name} -> true
      %{name: ^name} -> true
      _tool -> false
    end)
  end

  @spec tool_enabled?(t(), String.t()) :: boolean()
  def tool_enabled?(context, name) when is_binary(name), do: not is_nil(tool_spec(context, name))

  @spec restrict_tools(t(), [String.t()]) :: t()
  def restrict_tools(context, tool_names) when is_map(context) and is_list(tool_names) do
    allowed_names =
      tool_names
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    tool_specs = context |> tool_specs() |> filter_tool_specs(allowed_names)
    tool_metadata = Map.take(context.tool_metadata, MapSet.to_list(allowed_names))

    context
    |> Map.put(:tool_specs, tool_specs)
    |> Map.put(:tool_metadata, tool_metadata)
    |> Map.update(:source_context, nil, &restrict_source_context(&1, allowed_names))
  end

  def restrict_tools(context, _tool_names), do: context

  defp normalize_context(%{tool_specs: tool_specs} = context, opts) do
    source = Map.get(context, :source) || Source.from_opts(opts)
    source_context = Map.get(context, :source_context) || Source.default_context(source, opts)

    context
    |> Map.put(:source, source)
    |> Map.put(:source_context, source_context)
    |> Map.put_new(:source_kind, Source.kind(source, source_context))
    |> Map.put(:tool_specs, Spec.normalize_many(tool_specs))
    |> Map.put_new(:tool_metadata, Policy.metadata_many(tool_specs))
    |> Map.put_new(:tool_environment, %{})
    |> Map.put_new(:runtime_metadata, %{})
    |> put_workflow_settings(opts)
  end

  defp put_workflow_settings(context, opts) when is_map(context) and is_list(opts) do
    workflow_settings =
      Map.get(context, :workflow_settings) ||
        Map.get(context, "workflow_settings") ||
        Keyword.get(opts, :workflow_settings)

    if is_map(workflow_settings) do
      Map.put(context, :workflow_settings, workflow_settings)
    else
      context
    end
  end

  defp filter_tool_specs(tool_specs, allowed_names) when is_list(tool_specs) do
    Enum.filter(tool_specs, fn tool_spec ->
      case tool_name(tool_spec) do
        name when is_binary(name) -> MapSet.member?(allowed_names, name)
        _name -> false
      end
    end)
  end

  defp restrict_source_context(%{tool_specs: tool_specs} = source_context, allowed_names) do
    source_context
    |> Map.put(:tool_specs, filter_tool_specs(tool_specs, allowed_names))
    |> restrict_routes(allowed_names)
    |> restrict_sources(allowed_names)
  end

  defp restrict_source_context(source_context, _allowed_names), do: source_context

  defp restrict_routes(%{routes: routes} = source_context, allowed_names) when is_map(routes) do
    Map.put(source_context, :routes, Map.take(routes, MapSet.to_list(allowed_names)))
  end

  defp restrict_routes(source_context, _allowed_names), do: source_context

  defp restrict_sources(%{sources: sources} = source_context, allowed_names) when is_list(sources) do
    sources =
      Enum.map(sources, fn
        %{tool_specs: tool_specs} = source ->
          Map.put(source, :tool_specs, filter_tool_specs(tool_specs, allowed_names))

        source ->
          source
      end)

    Map.put(source_context, :sources, sources)
  end

  defp restrict_sources(source_context, _allowed_names), do: source_context

  defp tool_name(%{"name" => name}) when is_binary(name), do: name
  defp tool_name(%{name: name}) when is_binary(name), do: name
  defp tool_name(_tool_spec), do: nil
end
