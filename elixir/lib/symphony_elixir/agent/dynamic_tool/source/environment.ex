defmodule SymphonyElixir.Agent.DynamicTool.Source.Environment do
  @moduledoc false

  @type t :: %{optional(String.t()) => String.t()}

  @spec normalize(term()) :: {:ok, t()} | :error
  def normalize(environment) when is_map(environment), do: normalize_entries(Map.to_list(environment))
  def normalize(_environment), do: :error

  @spec normalize!(term()) :: t()
  def normalize!(environment) do
    case normalize(environment) do
      {:ok, normalized} ->
        normalized

      :error ->
        raise ArgumentError,
              "invalid dynamic tool source environment: expected a string-key/string-value map, got #{inspect(environment)}"
    end
  end

  defp normalize_entries(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn
      {key, value}, {:ok, acc} when is_binary(key) and key != "" and is_binary(value) ->
        {:cont, {:ok, Map.put(acc, key, value)}}

      {_key, nil}, {:ok, acc} ->
        {:cont, {:ok, acc}}

      _entry, _acc ->
        {:halt, :error}
    end)
  end
end
