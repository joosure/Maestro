defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization do
  @moduledoc false

  @payload_data_key "data"

  @spec value(term(), String.t()) :: term()
  def value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)

  def value(_map, _key), do: nil

  @spec string_value(term(), String.t()) :: String.t() | nil
  def string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) ->
        string_value_from_string(value)

      value when is_integer(value) ->
        Integer.to_string(value)

      value when is_atom(value) and not is_nil(value) ->
        value |> Atom.to_string() |> string_value_from_string()

      _value ->
        nil
    end
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

  @spec payload_value(term(), String.t()) :: term()
  def payload_value(payload, key) when is_map(payload) and is_binary(key) do
    data_value =
      payload
      |> payload_data()
      |> value(key)

    data_value || value(payload, key)
  end

  def payload_value(_payload, _key), do: nil

  @spec payload_data(term()) :: map()
  def payload_data(payload) when is_map(payload) do
    case value(payload, @payload_data_key) do
      data when is_map(data) -> data
      _other -> %{}
    end
  end

  def payload_data(_payload), do: %{}

  @spec present?(term()) :: boolean()
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(value), do: not is_nil(value)

  @spec present_values(term()) :: [String.t()]
  def present_values(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  def present_values(value) when is_integer(value), do: [Integer.to_string(value)]
  def present_values(value) when is_atom(value), do: present_values(Atom.to_string(value))
  def present_values(_value), do: []

  @spec string_list(term()) :: [String.t()]
  def string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(&present_values/1)
    |> Enum.map(&String.trim/1)
  end

  def string_list(_values), do: []

  @spec compact(map()) :: map()
  def compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
  end

  @spec deep_merge(map(), map()) :: map()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value), do: deep_merge(left_value, right_value), else: right_value
    end)
  end

  @spec generated_at() :: String.t()
  def generated_at, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp string_value_from_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end
end
