defmodule SymphonyElixir.Observability.EventStore.InputNormalizer do
  @moduledoc false

  @spec event(map()) :: map()
  def event(event) when is_map(event) do
    Map.new(event, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {to_string(key), value}
    end)
  end

  @spec context(map()) :: map()
  def context(context) when is_map(context) do
    context
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_context_value(value) do
        nil -> acc
        normalized_value -> Map.put(acc, normalize_context_key(key), normalized_value)
      end
    end)
  end

  defp normalize_context_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_context_key(key), do: to_string(key)

  defp normalize_context_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_context_value(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_context_value()
  end

  defp normalize_context_value(_value), do: nil
end
