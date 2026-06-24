defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.JsonValue do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @type scalar :: String.t() | number() | boolean() | nil
  @type t :: scalar() | [t()] | %{optional(String.t()) => t()}

  @spec normalize(term()) :: {:ok, t()} | {:error, term()}
  def normalize(value) when is_struct(value), do: invalid_json_value(value)

  def normalize(value) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn
      {key, nested_value}, {:ok, acc} when is_binary(key) ->
        case normalize(nested_value) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {key, _nested_value}, {:ok, _acc} ->
        {:halt, invalid_json_key(key)}
    end)
  end

  def normalize(value) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn nested_value, {:ok, acc} ->
      case normalize(nested_value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize(value) when is_binary(value), do: {:ok, value}
  def normalize(value) when is_boolean(value), do: {:ok, value}
  def normalize(value) when is_integer(value), do: {:ok, value}
  def normalize(value) when is_float(value), do: {:ok, value}
  def normalize(nil), do: {:ok, nil}
  def normalize(value), do: invalid_json_value(value)

  defp invalid_json_key(key), do: {:error, {:invalid_json_key, Diagnostics.detailed_type_atom(key)}}
  defp invalid_json_value(value), do: {:error, {:invalid_json_value, Diagnostics.detailed_type_atom(value)}}
end
