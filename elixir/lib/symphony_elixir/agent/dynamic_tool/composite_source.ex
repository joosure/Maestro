defmodule SymphonyElixir.Agent.DynamicTool.CompositeSource do
  @moduledoc """
  Aggregates multiple Dynamic Tool sources into one session-scoped source.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.{Conflict, Context, Entry, Route}
  alias SymphonyElixir.Agent.DynamicTool.Source
  alias SymphonyElixir.Agent.DynamicTool.Source.Config
  alias SymphonyElixir.Agent.DynamicTool.Source.Config.SourceSpec
  alias SymphonyElixir.Agent.DynamicTool.Spec

  @kind "composite"

  @type source_entry :: Entry.t()

  @type t :: Context.t()

  @spec default_context(keyword()) :: t()
  def default_context(opts \\ []) when is_list(opts) do
    source_specs = source_specs(opts)

    entries =
      source_specs
      |> Enum.flat_map(&build_entry(&1, opts))

    {tool_specs, routes, conflicts} = tool_specs_and_routes(entries)

    Context.new(%{
      sources: entries,
      tool_specs: tool_specs,
      routes: routes,
      conflicts: conflicts
    })
  end

  @spec kind() :: String.t()
  def kind, do: @kind

  @spec kind(term()) :: String.t()
  def kind(_source_context), do: kind()

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(source_context, _opts) do
    %Context{tool_specs: tool_specs} = Context.normalize(source_context)
    tool_specs
  end

  @spec environment(term(), keyword()) :: map()
  def environment(source_context, opts \\ [])

  def environment(source_context, opts) do
    %Context{sources: sources} = Context.normalize(source_context)

    Enum.reduce(sources, %{}, fn entry, acc ->
      entry
      |> source_environment(opts)
      |> merge_first_wins(acc)
    end)
  end

  @spec conflicts(term()) :: [Conflict.t()]
  def conflicts(source_context) do
    %Context{conflicts: conflicts} = Context.normalize(source_context)
    conflicts
  end

  @spec canonical_tool(term(), String.t() | nil) :: String.t() | nil
  def canonical_tool(source_context, tool) when is_binary(tool) do
    %Context{routes: routes} = Context.normalize(source_context)

    case Map.get(routes, tool) do
      %Route{source: source, source_context: source_context} ->
        Source.canonical_tool(source, source_context, tool)

      _route ->
        tool
    end
  end

  def canonical_tool(_source_context, tool), do: tool

  @spec execute(term(), String.t() | nil, term(), keyword()) :: Source.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(source_context, tool, arguments, opts) when is_binary(tool) and is_list(opts) do
    %Context{routes: routes} = Context.normalize(source_context)

    case Map.get(routes, tool) do
      %Route{source: source, source_context: source_context} ->
        Source.execute(source, source_context, tool, arguments, opts)

      _route ->
        {:error, {:unsupported_dynamic_tool, tool}}
    end
  end

  def execute(_source_context, tool, _arguments, _opts), do: {:error, {:unsupported_dynamic_tool, tool}}

  @spec execute_canonical(term(), String.t() | nil, String.t() | nil, term(), keyword()) :: Source.tool_result()
  def execute_canonical(source_context, provider_tool, canonical_tool, arguments, opts \\ [])

  def execute_canonical(source_context, provider_tool, canonical_tool, arguments, opts)
      when is_binary(provider_tool) and is_binary(canonical_tool) and is_list(opts) do
    %Context{routes: routes} = Context.normalize(source_context)

    case Map.get(routes, provider_tool) do
      %Route{source: source, source_context: source_context} ->
        case Source.canonical_tool(source, source_context, provider_tool) do
          ^canonical_tool ->
            Source.execute_canonical(source, source_context, provider_tool, canonical_tool, arguments, opts)

          resolved_canonical_tool ->
            {:error, {:canonical_dynamic_tool_mismatch, provider_tool, canonical_tool, resolved_canonical_tool}}
        end

      _route ->
        {:error, {:unsupported_dynamic_tool, provider_tool}}
    end
  end

  def execute_canonical(_source_context, provider_tool, _canonical_tool, _arguments, _opts),
    do: {:error, {:unsupported_dynamic_tool, provider_tool}}

  defp source_specs(opts) do
    Config.source_specs!(opts)
  end

  defp build_entry(%SourceSpec{} = source_spec, opts) do
    source_context = SourceSpec.source_context(source_spec, opts)
    tools = SourceSpec.tool_specs(source_spec, source_context, opts)

    entry(
      %{
        source: source_spec.source,
        source_context: source_context,
        source_kind: SourceSpec.source_kind(source_spec, source_context),
        tool_specs: tools
      },
      opts
    )
  end

  defp build_entry(_source_spec, _opts), do: []

  defp entry(attrs, _opts) do
    case Entry.new(attrs) do
      %Entry{} = entry -> [entry]
      nil -> []
    end
  end

  defp tool_specs_and_routes(entries) do
    {tool_specs, routes, _seen} =
      Enum.reduce(entries, {[], %{}, MapSet.new()}, fn entry, {tool_specs, routes, seen} ->
        Enum.reduce(entry.tool_specs, {tool_specs, routes, seen}, fn tool_spec, {tool_specs, routes, seen} ->
          name = Map.fetch!(tool_spec, Spec.name_key())

          route =
            Route.new(%{
              tool: name,
              source: entry.source,
              source_context: entry.source_context,
              source_kind: entry.source_kind
            })

          cond do
            is_nil(route) ->
              {tool_specs, routes, seen}

            MapSet.member?(seen, name) ->
              {tool_specs, Map.update!(routes, name, &add_conflict(&1, route)), seen}

            true ->
              {[tool_spec | tool_specs], Map.put(routes, name, %{route: route, conflicts: []}), MapSet.put(seen, name)}
          end
        end)
      end)

    conflicts =
      routes
      |> Map.values()
      |> Enum.flat_map(fn %{conflicts: conflicts} -> conflicts end)
      |> Enum.reverse()

    {Enum.reverse(tool_specs), Map.new(routes, fn {name, %{route: route}} -> {name, route} end), conflicts}
  end

  defp add_conflict(%{route: kept_route, conflicts: conflicts} = existing, rejected_route) do
    conflict =
      Conflict.new(%{
        tool: kept_route.tool,
        kept_route: kept_route,
        rejected_route: rejected_route
      })

    Map.put(existing, :conflicts, [conflict | conflicts])
  end

  defp source_environment(%Entry{source: source, source_context: source_context}, opts) do
    Source.environment(source, source_context, opts)
  end

  defp source_environment(_entry, _opts), do: %{}

  defp merge_first_wins(new_env, acc) when is_map(new_env) and is_map(acc) do
    Map.merge(new_env, acc)
  end
end
