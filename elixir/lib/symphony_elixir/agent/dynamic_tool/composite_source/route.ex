defmodule SymphonyElixir.Agent.DynamicTool.CompositeSource.Route do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Source.Kind

  defstruct tool: nil,
            source: nil,
            source_context: nil,
            source_kind: nil

  @type t :: %__MODULE__{
          tool: String.t(),
          source: module(),
          source_context: term(),
          source_kind: String.t() | nil
        }

  @spec new(keyword() | map()) :: t() | nil
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    source = value(attrs, :source, nil)
    tool = normalize_tool(value(attrs, :tool, nil))

    if is_atom(source) and not is_nil(source) and is_binary(tool) do
      %__MODULE__{
        tool: tool,
        source: source,
        source_context: value(attrs, :source_context, nil),
        source_kind: Kind.normalize(value(attrs, :source_kind, nil))
      }
    end
  end

  @spec normalize(term(), String.t() | nil) :: t() | nil
  def normalize(%__MODULE__{} = route, fallback_tool), do: route |> maybe_put_tool(fallback_tool) |> new()

  def normalize(route, fallback_tool) when is_map(route) or is_list(route) do
    route
    |> maybe_put_tool(fallback_tool)
    |> new()
  end

  def normalize(_route, _fallback_tool), do: nil

  defp maybe_put_tool(attrs, fallback_tool) when is_map(attrs) or is_list(attrs) do
    if normalize_tool(value(attrs, :tool, nil)) do
      attrs
    else
      put_value(attrs, :tool, fallback_tool)
    end
  end

  defp normalize_tool(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_tool(_value), do: nil

  defp value(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp value(attrs, key, default) when is_map(attrs) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> default
    end
  end

  defp put_value(attrs, key, value) when is_list(attrs), do: Keyword.put(attrs, key, value)
  defp put_value(attrs, key, value) when is_map(attrs), do: Map.put(attrs, key, value)
end
