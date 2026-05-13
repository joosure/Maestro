defmodule SymphonyWorkerDaemon.Protocol.QueryParams do
  @moduledoc false

  @session_filter_keys ["owner", "tenant_id", "run_id", "status"]
  @event_filter_keys ["after_event_id", "limit"]

  @spec session(map() | keyword()) :: String.t()
  def session(filters) when is_map(filters) or is_list(filters) do
    filters
    |> filter_pairs(@session_filter_keys)
    |> URI.encode_query()
  end

  @spec events(map() | keyword()) :: String.t()
  def events(filters) when is_map(filters) or is_list(filters) do
    filters
    |> filter_pairs(@event_filter_keys)
    |> URI.encode_query()
  end

  defp filter_pairs(filters, allowed_keys) when is_map(filters) do
    filters
    |> Map.take(allowed_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(optional_string(value)) end)
    |> Map.new(fn {key, value} -> {key, optional_string(value)} end)
  end

  defp filter_pairs(filters, allowed_keys) when is_list(filters) do
    Enum.reduce(filters, %{}, fn {key, value}, acc ->
      string_key = to_string(key)

      if string_key in allowed_keys and optional_string(value) do
        Map.put(acc, string_key, optional_string(value))
      else
        acc
      end
    end)
  end

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp optional_string(_value), do: nil
end
