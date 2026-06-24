defmodule SymphonyElixir.Observability.Event do
  @moduledoc """
  Canonical event envelope used by the Elixir implementation's observability layer.
  """

  alias SymphonyElixir.Observability.{EventContract, Fields}

  @spec build(atom(), atom() | String.t(), map()) :: map()
  def build(level, event, fields \\ %{}) when is_map(fields) do
    normalized_fields = normalize_map(fields)
    component = Map.get(normalized_fields, EventContract.component_key(), EventContract.unknown_component())
    message = Map.get(normalized_fields, EventContract.message_key(), default_message(event, normalized_fields))

    normalized_fields
    |> Map.drop([EventContract.component_key(), EventContract.message_key()])
    |> Map.merge(%{
      EventContract.timestamp_key() => DateTime.utc_now(:millisecond) |> DateTime.to_iso8601(),
      EventContract.level_key() => level_to_string(level),
      EventContract.event_key() => event_to_string(event),
      EventContract.message_key() => message,
      EventContract.service_key() => EventContract.service_name(),
      EventContract.component_key() => component
    })
    |> drop_nil_values()
  end

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_value(value)} end)
  end

  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_boolean(value) or is_binary(value), do: value
  defp normalize_value(value) when is_integer(value) or is_float(value), do: value
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_value(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize_value(%Time{} = value), do: Time.to_iso8601(value)

  defp normalize_value(%_{} = value) do
    value
    |> Map.from_struct()
    |> normalize_map()
  end

  defp normalize_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&normalize_value/1)
  defp normalize_value(value), do: inspect(value)

  defp drop_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp event_to_string(event) when is_atom(event), do: Atom.to_string(event)
  defp event_to_string(event), do: to_string(event)

  defp level_to_string(level) when is_atom(level), do: Atom.to_string(level)
  defp level_to_string(level), do: to_string(level)

  defp default_message(event, fields) when is_map(fields) do
    [event_to_string(event)]
    |> append_context_fields(fields)
    |> append_summary_field(fields, EventContract.result_summary_key())
    |> append_summary_field(fields, EventContract.payload_summary_key())
    |> append_error_field(fields)
    |> Enum.join(" ")
  end

  defp append_context_fields(parts, fields) when is_list(parts) and is_map(fields) do
    Enum.reduce(Fields.message_context_fields(), parts, fn key, acc ->
      append_key_value(acc, key, Map.get(fields, key))
    end)
  end

  defp append_summary_field(parts, fields, key) when is_list(parts) and is_map(fields) do
    case Map.get(fields, key) do
      nil -> parts
      "" -> parts
      value -> append_key_value(parts, key, value)
    end
  end

  defp append_error_field(parts, fields) when is_list(parts) and is_map(fields) do
    append_key_value(parts, EventContract.error_key(), Map.get(fields, EventContract.error_key()))
  end

  defp append_key_value(parts, _key, nil), do: parts
  defp append_key_value(parts, _key, ""), do: parts
  defp append_key_value(parts, key, value), do: parts ++ ["#{key}=#{format_message_value(value)}"]

  defp format_message_value(value) when is_binary(value) do
    cond do
      not String.valid?(value) -> inspect(value)
      String.match?(value, ~r/\s/u) -> inspect(value)
      true -> value
    end
  end

  defp format_message_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_message_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp format_message_value(value) when is_boolean(value), do: to_string(value)
  defp format_message_value(value), do: inspect(value)
end
