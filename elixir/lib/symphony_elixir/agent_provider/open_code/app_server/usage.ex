defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.Usage do
  @moduledoc false

  @type token_usage :: %{
          input: non_neg_integer(),
          output: non_neg_integer(),
          reasoning: non_neg_integer(),
          total: non_neg_integer()
        }

  @spec event_usage(String.t(), map()) :: token_usage() | nil
  def event_usage("message.updated", %{"info" => info}), do: message_info_token_usage(info)
  def event_usage("message.part.updated", %{"part" => part}), do: part_token_usage(part)
  def event_usage(_type, _properties), do: nil

  @spec message_response_token_usage(map()) :: token_usage() | nil
  def message_response_token_usage(%{"info" => info}) when is_map(info), do: message_info_token_usage(info)
  def message_response_token_usage(_response), do: nil

  @spec message_turn_id(map()) :: String.t() | nil
  def message_turn_id(%{"info" => %{"id" => id}}) when is_binary(id), do: id
  def message_turn_id(%{"id" => id}) when is_binary(id), do: id
  def message_turn_id(_response), do: nil

  defp message_info_token_usage(%{"tokens" => tokens}), do: normalize_token_usage(tokens)
  defp message_info_token_usage(_info), do: nil

  defp part_token_usage(%{"type" => "step-finish", "tokens" => tokens}), do: normalize_token_usage(tokens)
  defp part_token_usage(_part), do: nil

  defp normalize_token_usage(tokens) when is_map(tokens) do
    input = token_value(tokens, ["input", :input])
    output = token_value(tokens, ["output", :output])
    reasoning = token_value(tokens, ["reasoning", :reasoning])

    %{input: input, output: output, reasoning: reasoning, total: input + output + reasoning}
  end

  defp normalize_token_usage(_tokens), do: nil

  defp token_value(tokens, keys) do
    case Enum.find_value(keys, &Map.get(tokens, &1)) do
      value when is_integer(value) and value >= 0 -> value
      _value -> 0
    end
  end
end
