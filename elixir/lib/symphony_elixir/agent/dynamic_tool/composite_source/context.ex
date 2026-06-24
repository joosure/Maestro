defmodule SymphonyElixir.Agent.DynamicTool.CompositeSource.Context do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.{Conflict, Entry, Route}
  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Agent.DynamicTool.Spec

  defstruct sources: [],
            tool_specs: [],
            routes: %{},
            conflicts: []

  @type t :: %__MODULE__{
          sources: [Entry.t()],
          tool_specs: [map()],
          routes: %{optional(String.t()) => Route.t()},
          conflicts: [Conflict.t()]
        }

  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @spec new(keyword() | map()) :: t()
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    %__MODULE__{
      sources: entries(value(attrs, :sources, [])),
      tool_specs: tool_specs(value(attrs, :tool_specs, [])),
      routes: routes(value(attrs, :routes, %{})),
      conflicts: conflicts(value(attrs, :conflicts, []))
    }
  end

  @spec normalize(term()) :: t()
  def normalize(%__MODULE__{} = context), do: new(context)
  def normalize(context) when is_map(context) or is_list(context), do: new(context)
  def normalize(_context), do: empty()

  defp entries(entries) when is_list(entries) do
    entries
    |> Enum.map(&Entry.normalize/1)
    |> Enum.reject(&is_nil/1)
  end

  defp entries(_entries), do: []

  defp tool_specs(tool_specs) when is_list(tool_specs), do: Enum.flat_map(tool_specs, &canonical_tool_spec/1)
  defp tool_specs(_tool_specs), do: []

  defp canonical_tool_spec(tool_spec) when is_map(tool_spec) do
    case Spec.normalize(tool_spec) do
      {:ok, normalized_spec} ->
        [Map.merge(normalized_spec, tool_spec |> Metadata.normalize() |> Metadata.to_map())]

      :error ->
        []
    end
  end

  defp canonical_tool_spec(_tool_spec), do: []

  defp routes(routes) when is_map(routes) do
    routes
    |> Enum.flat_map(fn {tool, route} ->
      case Route.normalize(route, normalize_tool_name(tool)) do
        %Route{tool: route_tool} = route when is_binary(route_tool) -> [{route_tool, route}]
        _route -> []
      end
    end)
    |> Map.new()
  end

  defp routes(_routes), do: %{}

  defp conflicts(conflicts) when is_list(conflicts) do
    conflicts
    |> Enum.map(&Conflict.normalize/1)
    |> Enum.reject(&is_nil/1)
  end

  defp conflicts(_conflicts), do: []

  defp normalize_tool_name(tool) when is_binary(tool) do
    case String.trim(tool) do
      "" -> nil
      tool -> tool
    end
  end

  defp normalize_tool_name(_tool), do: nil

  defp value(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp value(attrs, key, default) when is_map(attrs) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> default
    end
  end
end
