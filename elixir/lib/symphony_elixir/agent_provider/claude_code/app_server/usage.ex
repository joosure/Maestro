defmodule SymphonyElixir.AgentProvider.ClaudeCode.AppServer.Usage do
  @moduledoc false

  @spec assistant_usage(map()) :: map() | nil
  def assistant_usage(%{"message" => %{"usage" => usage}}) when is_map(usage), do: usage
  def assistant_usage(%{message: %{usage: usage}}) when is_map(usage), do: usage
  def assistant_usage(_payload), do: nil

  @spec result_usage(map()) :: map()
  def result_usage(%{"usage" => usage}) when is_map(usage), do: normalize_usage(usage)
  def result_usage(_payload), do: %{}

  @spec result_turn_id(map()) :: String.t() | nil
  def result_turn_id(%{"uuid" => uuid}) when is_binary(uuid), do: uuid
  def result_turn_id(%{"message" => %{"id" => message_id}}) when is_binary(message_id), do: message_id
  def result_turn_id(_payload), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    input = token_value(usage, ["input", "input_tokens", :input, :input_tokens])
    output = token_value(usage, ["output", "output_tokens", :output, :output_tokens])
    reasoning = token_value(usage, ["reasoning", "reasoning_tokens", :reasoning, :reasoning_tokens])
    total = token_value_or_nil(usage, ["total", "total_tokens", :total, :total_tokens]) || input + output + reasoning

    %{input: input, output: output, reasoning: reasoning, total: total}
  end

  defp token_value_or_nil(usage, keys) do
    case Enum.find_value(keys, &Map.get(usage, &1)) do
      value when is_integer(value) and value >= 0 -> value
      _ -> nil
    end
  end

  defp token_value(usage, keys) do
    case Enum.find_value(keys, &Map.get(usage, &1)) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end
end
