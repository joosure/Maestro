defmodule SymphonyElixir.Workflow.RoutePolicy.Keys do
  @moduledoc false

  @spec route_keys(module()) :: [atom()]
  def route_keys(profile_module) when is_atom(profile_module) do
    profile_module.route_keys()
  end

  @spec route_key?(term(), module()) :: boolean()
  def route_key?(route_key, profile_module), do: not is_nil(normalize_route_key(route_key, profile_module))

  @spec normalize_route_key(term(), module()) :: atom() | nil
  def normalize_route_key(route_key, profile_module) when is_atom(route_key) and is_atom(profile_module) do
    if route_key in route_keys(profile_module), do: route_key, else: nil
  end

  def normalize_route_key(route_key, profile_module) when is_binary(route_key) and is_atom(profile_module) do
    normalized_route_key = normalize_name(route_key)

    Enum.find(route_keys(profile_module), &(Atom.to_string(&1) == normalized_route_key))
  end

  def normalize_route_key(_route_key, _profile_module), do: nil

  defp normalize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      trimmed ->
        trimmed
        |> String.downcase()
        |> String.replace(~r/[\s-]+/, "_")
    end
  end
end
