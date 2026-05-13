defmodule SymphonyElixir.Tracker.Tapd.Client.Fields do
  @moduledoc false

  @spec normalize_keys_to_strings(map()) :: map()
  def normalize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  @spec string_field(map(), String.t()) :: term()
  def string_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  @spec normalize_string(term()) :: String.t() | nil
  def normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_string(value), do: if(value in [nil, ""], do: nil, else: to_string(value))
end
