defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry.Values do
  @moduledoc false

  @name_pattern ~r/^[a-z][a-z0-9_]*$/

  @spec normalize_name(term()) :: String.t() | nil
  def normalize_name(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_name()
  end

  def normalize_name(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[\s-]+/, "_")

    if Regex.match?(@name_pattern, normalized), do: normalized
  end

  def normalize_name(_value), do: nil

  @spec normalize_non_empty_string(term()) :: String.t() | nil
  def normalize_non_empty_string(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_non_empty_string()
  end

  def normalize_non_empty_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_non_empty_string(_value), do: nil

  @spec normalize_positive_integer(term()) :: pos_integer() | nil
  def normalize_positive_integer(value) when is_integer(value) and value > 0, do: value

  def normalize_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {version, ""} when version > 0 -> version
      _other -> nil
    end
  end

  def normalize_positive_integer(_value), do: nil

  @spec normalize_map(term()) :: map()
  def normalize_map(value) when is_map(value), do: value
  def normalize_map(_value), do: %{}

  @spec map_field(map() | keyword() | term(), atom()) :: term()
  def map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  def map_field(map, key) when is_list(map) and is_atom(key) do
    case List.keyfind(map, key, 0) || List.keyfind(map, Atom.to_string(key), 0) do
      {_matched_key, value} -> value
      nil -> nil
    end
  end

  def map_field(_map, _key), do: nil

  @spec registry_entry_pair_list?(term()) :: boolean()
  def registry_entry_pair_list?(raw_entry) when is_list(raw_entry) do
    Enum.all?(raw_entry, fn
      {key, _value} when is_atom(key) or is_binary(key) -> true
      _other -> false
    end)
  end

  def registry_entry_pair_list?(_raw_entry), do: false
end
