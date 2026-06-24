defmodule SymphonyElixir.Agent.DynamicTool.Serializer do
  @moduledoc """
  JSON-safe serialization helpers for dynamic tool provider boundaries.

  This module is the last-mile JSON sanitizer. It does not interpret domain
  error structs; known error types must be projected before they reach this
  serializer.
  """

  alias SymphonyElixir.Agent.DynamicTool.ErrorProjector.Contract

  @spec public_error_details(map() | nil) :: map() | nil
  def public_error_details(details) when is_map(details) do
    details
    |> canonical_public_error_details()
    |> case do
      sanitized when map_size(sanitized) == 0 -> nil
      sanitized -> sanitized
    end
  end

  def public_error_details(_details), do: nil

  @spec json_safe_map(map()) :: map()
  def json_safe_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {json_safe_key(key), json_safe_value(value)} end)
  end

  @spec canonical_json_safe_map(map()) :: map()
  def canonical_json_safe_map(map) when is_map(map) do
    map
    |> Enum.flat_map(fn
      {key, value} when is_binary(key) -> [{key, json_safe_value(value)}]
      {_key, _value} -> []
    end)
    |> Map.new()
  end

  @spec json_safe_value(term()) :: term()
  def json_safe_value(%_{} = value), do: inspect(value)
  def json_safe_value(map) when is_map(map), do: json_safe_map(map)
  def json_safe_value(list) when is_list(list), do: Enum.map(list, &json_safe_value/1)
  def json_safe_value(value) when is_boolean(value) or is_nil(value), do: value
  def json_safe_value(value) when is_atom(value), do: Atom.to_string(value)
  def json_safe_value(value) when is_tuple(value), do: inspect(value)
  def json_safe_value(value), do: value

  @spec json_safe_key(term()) :: String.t()
  def json_safe_key(key) when is_binary(key), do: key
  def json_safe_key(key) when is_atom(key), do: Atom.to_string(key)
  def json_safe_key(key) when is_integer(key), do: Integer.to_string(key)
  def json_safe_key(key), do: inspect(key)

  @spec maybe_put(map(), String.t(), term()) :: map()
  def maybe_put(payload, _key, nil), do: payload
  def maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp canonical_public_error_details(details) do
    allowed_keys = Contract.public_detail_keys()

    details
    |> canonical_json_safe_map()
    |> Map.take(allowed_keys)
  end
end
