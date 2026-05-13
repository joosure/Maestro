defmodule SymphonyWorkerDaemon.Session.Filters do
  @moduledoc false

  @type t :: map() | keyword()

  @filter_keys [
    {"owner", :owner},
    {"tenant_id", :tenant_id},
    {"run_id", :run_id},
    {"status", :status}
  ]

  @spec matches?(map(), t()) :: boolean()
  def matches?(summary, filters) when is_map(summary) and (is_map(filters) or is_list(filters)) do
    Enum.all?(@filter_keys, fn {string_key, atom_key} ->
      case filter_value(filters, string_key, atom_key) do
        nil -> true
        value -> Map.get(summary, string_key) == value
      end
    end)
  end

  defp filter_value(filters, string_key, atom_key) when is_map(filters) do
    normalize_filter_value(Map.get(filters, string_key) || Map.get(filters, atom_key))
  end

  defp filter_value(filters, string_key, atom_key) when is_list(filters) do
    normalize_filter_value(Keyword.get(filters, atom_key) || string_key_value(filters, string_key))
  end

  defp string_key_value(filters, key) do
    Enum.find_value(filters, fn
      {^key, value} -> value
      _entry -> nil
    end)
  end

  defp normalize_filter_value(nil), do: nil

  defp normalize_filter_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_filter_value(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_filter_value()
  defp normalize_filter_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_filter_value(_value), do: nil
end
