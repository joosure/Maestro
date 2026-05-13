defmodule SymphonyElixir.Agent.DynamicTool.CompositeSource do
  @moduledoc """
  Aggregates multiple Dynamic Tool sources into one session-scoped source.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Agent.DynamicTool.{Source, Spec}

  @default_child_sources [
    Module.concat(["SymphonyElixir", "Tracker", "DynamicToolSource"]),
    Module.concat(["SymphonyElixir", "Repo", "DynamicToolSource"]),
    Module.concat(["SymphonyElixir", "RepoProvider", "DynamicToolSource"])
  ]

  @type source_entry :: %{
          source: module(),
          source_context: term(),
          source_kind: String.t() | nil,
          tool_specs: [map()]
        }

  @type t :: %{
          sources: [source_entry()],
          tool_specs: [map()],
          routes: map()
        }

  @spec default_context(keyword()) :: t()
  def default_context(opts \\ []) when is_list(opts) do
    source_specs = source_specs(opts)

    entries =
      source_specs
      |> Enum.flat_map(&build_entry(&1, opts))

    {tool_specs, routes} = tool_specs_and_routes(entries)

    %{
      sources: entries,
      tool_specs: tool_specs,
      routes: routes
    }
  end

  @spec kind(term()) :: String.t()
  def kind(_source_context), do: "composite"

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(%{tool_specs: tool_specs}, _opts) when is_list(tool_specs), do: tool_specs
  def tools(_source_context, _opts), do: []

  @spec environment(term(), keyword()) :: map()
  def environment(source_context, opts \\ [])

  def environment(%{sources: sources}, opts) when is_list(sources) do
    Enum.reduce(sources, %{}, fn entry, acc ->
      entry
      |> source_environment(opts)
      |> merge_first_wins(acc)
    end)
  end

  def environment(_source_context, _opts), do: %{}

  @spec execute(term(), String.t() | nil, term(), keyword()) :: Source.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(%{routes: routes}, tool, arguments, opts) when is_map(routes) and is_binary(tool) and is_list(opts) do
    case Map.get(routes, tool) do
      %{source: source, source_context: source_context} ->
        Source.execute(source, source_context, tool, arguments, opts)

      _route ->
        {:error, {:unsupported_dynamic_tool, tool}}
    end
  end

  def execute(_source_context, tool, _arguments, _opts), do: {:error, {:unsupported_dynamic_tool, tool}}

  defp source_specs(opts) do
    opts
    |> Keyword.get_lazy(:dynamic_tool_sources, fn ->
      Application.get_env(:symphony_elixir, :dynamic_tool_sources, @default_child_sources)
    end)
    |> normalize_source_specs()
  end

  defp normalize_source_specs(source_specs) when is_list(source_specs), do: source_specs
  defp normalize_source_specs(_source_specs), do: []

  defp build_entry(source, opts) when is_atom(source) do
    source_context = Source.default_context(source, opts)
    tools = Source.tools(source, source_context, opts)

    [
      %{
        source: source,
        source_context: source_context,
        source_kind: Source.kind(source, source_context),
        tool_specs: tools
      }
    ]
  end

  defp build_entry({source, source_context}, opts) when is_atom(source) do
    tools = Source.tools(source, source_context, opts)

    [
      %{
        source: source,
        source_context: source_context,
        source_kind: Source.kind(source, source_context),
        tool_specs: tools
      }
    ]
  end

  defp build_entry(%{source: source} = source_spec, opts) when is_atom(source) do
    source_context =
      Map.get_lazy(source_spec, :source_context, fn ->
        Map.get_lazy(source_spec, :context, fn -> Source.default_context(source, opts) end)
      end)

    tools = Map.get_lazy(source_spec, :tool_specs, fn -> Source.tools(source, source_context, opts) end)

    [
      %{
        source: source,
        source_context: source_context,
        source_kind: Map.get(source_spec, :source_kind) || Source.kind(source, source_context),
        tool_specs: tools
      }
    ]
  end

  defp build_entry(_source_spec, _opts), do: []

  defp tool_specs_and_routes(entries) do
    {tool_specs, routes, _seen} =
      Enum.reduce(entries, {[], %{}, MapSet.new()}, fn entry, {tool_specs, routes, seen} ->
        Enum.reduce(entry.tool_specs, {tool_specs, routes, seen}, fn tool_spec, {tool_specs, routes, seen} ->
          case Spec.normalize(tool_spec) do
            {:ok, %{"name" => name}} ->
              if MapSet.member?(seen, name) do
                {tool_specs, routes, seen}
              else
                route = %{
                  source: entry.source,
                  source_context: entry.source_context,
                  source_kind: entry.source_kind
                }

                {[tool_spec | tool_specs], Map.put(routes, name, route), MapSet.put(seen, name)}
              end

            :error ->
              {tool_specs, routes, seen}
          end
        end)
      end)

    {Enum.reverse(tool_specs), routes}
  end

  defp source_environment(%{source: source, source_context: source_context}, opts) do
    Source.environment(source, source_context, opts)
  end

  defp source_environment(_entry, _opts), do: %{}

  defp merge_first_wins(new_env, acc) when is_map(new_env) and is_map(acc) do
    Map.merge(new_env, acc)
  end
end
