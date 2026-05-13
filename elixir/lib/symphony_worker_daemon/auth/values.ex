defmodule SymphonyWorkerDaemon.Auth.Values do
  @moduledoc false

  @spec normalize_optional_string(term()) :: String.t() | nil
  def normalize_optional_string(nil), do: nil

  def normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  def normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_optional_string(_value), do: nil

  @spec value(map() | keyword() | term(), atom()) :: term()
  def value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  def value(keyword, key) when is_list(keyword), do: Keyword.get(keyword, key) || string_key_value(keyword, Atom.to_string(key))
  def value(_data, _key), do: nil

  @spec known_value(map(), String.t(), atom()) :: term()
  def known_value(map, string_key, atom_key) do
    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  @spec truthy?(term()) :: boolean()
  def truthy?(true), do: true
  def truthy?("true"), do: true
  def truthy?("1"), do: true
  def truthy?(1), do: true
  def truthy?(_value), do: false

  @spec maybe_put_tenant(map(), String.t() | nil) :: map()
  def maybe_put_tenant(map, nil), do: map
  def maybe_put_tenant(map, tenant_id) when is_binary(tenant_id), do: Map.put(map, :tenant_id, tenant_id)

  @spec maybe_put_string(map(), String.t(), String.t() | nil) :: map()
  def maybe_put_string(map, _key, nil), do: map
  def maybe_put_string(map, key, value) when is_binary(key) and is_binary(value), do: Map.put(map, key, value)

  @spec compact_map(map()) :: map()
  def compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp string_key_value(keyword, key) do
    Enum.find_value(keyword, fn
      {^key, value} -> value
      _entry -> nil
    end)
  end
end
