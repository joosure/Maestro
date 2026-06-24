defmodule SymphonyElixir.Agent.DynamicTool.CompositeSource.Conflict do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.Route

  defstruct tool: nil,
            kept_route: nil,
            rejected_route: nil

  @type t :: %__MODULE__{
          tool: String.t(),
          kept_route: Route.t(),
          rejected_route: Route.t()
        }

  @spec new(keyword() | map()) :: t() | nil
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    tool = normalized_string(value(attrs, :tool, nil))
    kept_route = Route.normalize(value(attrs, :kept_route, nil), tool)
    rejected_route = Route.normalize(value(attrs, :rejected_route, nil), tool)

    if is_binary(tool) and match?(%Route{}, kept_route) and match?(%Route{}, rejected_route) do
      %__MODULE__{
        tool: tool,
        kept_route: kept_route,
        rejected_route: rejected_route
      }
    end
  end

  @spec normalize(term()) :: t() | nil
  def normalize(%__MODULE__{} = conflict), do: new(conflict)
  def normalize(conflict) when is_map(conflict) or is_list(conflict), do: new(conflict)
  def normalize(_conflict), do: nil

  defp normalized_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalized_string(_value), do: nil

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
