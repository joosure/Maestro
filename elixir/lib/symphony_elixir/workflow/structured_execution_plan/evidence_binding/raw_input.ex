defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput do
  @moduledoc """
  Boundary helpers for typed-tool payloads and runtime metadata.

  These helpers intentionally accept string-keyed and atom-keyed maps because
  they run only at the external tool-result boundary. Canonical runtime records
  should use field contracts directly instead of this module.
  """

  @runtime_metadata_key "runtime_metadata"
  @runtime_metadata_atom_key :runtime_metadata

  @spec runtime_metadata_key() :: String.t()
  def runtime_metadata_key, do: @runtime_metadata_key

  @spec runtime_metadata(term()) :: map()
  def runtime_metadata(%{@runtime_metadata_atom_key => metadata}) when is_map(metadata), do: metadata
  def runtime_metadata(%{@runtime_metadata_key => metadata}) when is_map(metadata), do: metadata
  def runtime_metadata(_context), do: %{}

  @spec map_value(term(), atom()) :: term()
  def map_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  def map_value(_map, _key), do: nil

  @spec value(term(), String.t()) :: term()
  def value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  def value(_map, _key), do: nil

  @spec string_value(term(), String.t()) :: String.t() | nil
  def string_value(map, key) do
    case value(map, key) do
      nil -> nil
      value when is_binary(value) -> trim_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) -> value |> Atom.to_string() |> trim_string()
      _value -> nil
    end
  end

  @spec string_list(term()) :: [String.t()]
  def string_list(values) when is_list(values), do: Enum.flat_map(values, &present_values/1)
  def string_list(_values), do: []

  @spec first_present([term()]) :: String.t() | nil
  def first_present(values) do
    values
    |> Enum.flat_map(&present_values/1)
    |> List.first()
  end

  @spec integer_value(term(), String.t()) :: integer() | nil
  def integer_value(map, key) when is_map(map) do
    case value(map, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _value -> nil
    end
  end

  def integer_value(_map, _key), do: nil

  @spec list_length(term()) :: non_neg_integer()
  def list_length(values) when is_list(values), do: length(values)
  def list_length(_values), do: 0

  @spec compact(map()) :: map()
  def compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp present_values(nil), do: []

  defp present_values(value) when is_binary(value) do
    case trim_string(value) do
      nil -> []
      trimmed -> [trimmed]
    end
  end

  defp present_values(value) when is_integer(value), do: [Integer.to_string(value)]
  defp present_values(value) when is_atom(value), do: value |> Atom.to_string() |> present_values()
  defp present_values(_value), do: []

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp trim_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
