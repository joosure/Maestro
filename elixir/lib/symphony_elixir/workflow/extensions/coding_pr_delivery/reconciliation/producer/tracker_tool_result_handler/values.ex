defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Values do
  @moduledoc false

  @spec required_string(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def required_string(map, key) when is_map(map) and is_binary(key) do
    case string_value(map, key) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:error, {:missing_required_argument, key}}
    end
  end

  @spec string_value(map(), String.t()) :: String.t() | nil
  def string_value(map, key) when is_map(map) and is_binary(key) do
    map
    |> map_value(key)
    |> normalize_string()
  end

  def string_value(_map, _key), do: nil

  @spec map_value(map(), String.t()) :: term() | nil
  def map_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key)
  end

  def map_value(_map, _key), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil
end
