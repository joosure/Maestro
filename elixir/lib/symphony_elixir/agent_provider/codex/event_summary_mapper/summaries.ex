defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Summaries do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{Access, Text}

  @spec format_usage_counts(term()) :: String.t() | nil
  def format_usage_counts(usage) when is_map(usage) do
    input =
      Text.parse_integer(
        Access.map_value(usage, [
          "input_tokens",
          :input_tokens,
          "prompt_tokens",
          :prompt_tokens,
          "inputTokens",
          :inputTokens,
          "promptTokens",
          :promptTokens
        ])
      )

    output =
      Text.parse_integer(
        Access.map_value(usage, [
          "output_tokens",
          :output_tokens,
          "completion_tokens",
          :completion_tokens,
          "outputTokens",
          :outputTokens,
          "completionTokens",
          :completionTokens
        ])
      )

    total =
      Text.parse_integer(
        Access.map_value(usage, [
          "total_tokens",
          :total_tokens,
          "total",
          :total,
          "totalTokens",
          :totalTokens
        ])
      )

    parts =
      []
      |> append_usage_part("in", input)
      |> append_usage_part("out", output)
      |> append_usage_part("total", total)

    case parts do
      [] -> nil
      _ -> Enum.join(parts, ", ")
    end
  end

  def format_usage_counts(_usage), do: nil

  @spec format_rate_limits_summary(term()) :: String.t()
  def format_rate_limits_summary(nil), do: "n/a"

  def format_rate_limits_summary(rate_limits) when is_map(rate_limits) do
    primary = Access.map_value(rate_limits, ["primary", :primary])
    secondary = Access.map_value(rate_limits, ["secondary", :secondary])

    primary_text = format_rate_limit_bucket_summary(primary)
    secondary_text = format_rate_limit_bucket_summary(secondary)

    cond do
      primary_text != nil and secondary_text != nil ->
        "primary #{primary_text}; secondary #{secondary_text}"

      primary_text != nil ->
        "primary #{primary_text}"

      secondary_text != nil ->
        "secondary #{secondary_text}"

      true ->
        "n/a"
    end
  end

  def format_rate_limits_summary(_rate_limits), do: "n/a"

  @spec format_streaming_event(String.t(), term()) :: String.t()
  def format_streaming_event(label, payload) do
    case extract_delta_preview(payload) do
      nil -> label
      preview -> "#{label}: #{preview}"
    end
  end

  @spec format_reasoning_update(term()) :: String.t()
  def format_reasoning_update(payload) do
    case extract_reasoning_focus(payload) do
      nil -> "reasoning update"
      focus -> "reasoning update: #{focus}"
    end
  end

  @spec extract_reasoning_focus(term()) :: String.t() | nil
  def extract_reasoning_focus(payload) do
    value = Access.extract_first_path(payload, reasoning_focus_paths())

    if is_binary(value) do
      trimmed = String.trim(value)
      if trimmed == "", do: nil, else: Text.inline_text(trimmed)
    else
      nil
    end
  end

  @spec extract_delta_preview(term()) :: String.t() | nil
  def extract_delta_preview(payload) do
    delta = Access.extract_first_path(payload, delta_paths())

    case delta do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: Text.inline_text(trimmed)

      _ ->
        nil
    end
  end

  @spec token_usage_paths() :: [[term()]]
  def token_usage_paths do
    [
      ["params", "msg", "payload", "info", "total_token_usage"],
      [:params, :msg, :payload, :info, :total_token_usage],
      ["params", "msg", "info", "total_token_usage"],
      [:params, :msg, :info, :total_token_usage],
      ["params", "tokenUsage", "total"],
      [:params, :tokenUsage, :total]
    ]
  end

  @spec delta_paths() :: [[term()]]
  def delta_paths do
    [
      ["params", "delta"],
      [:params, :delta],
      ["params", "msg", "delta"],
      [:params, :msg, :delta],
      ["params", "textDelta"],
      [:params, :textDelta],
      ["params", "msg", "textDelta"],
      [:params, :msg, :textDelta],
      ["params", "outputDelta"],
      [:params, :outputDelta],
      ["params", "msg", "outputDelta"],
      [:params, :msg, :outputDelta],
      ["params", "text"],
      [:params, :text],
      ["params", "msg", "text"],
      [:params, :msg, :text],
      ["params", "summaryText"],
      [:params, :summaryText],
      ["params", "msg", "summaryText"],
      [:params, :msg, :summaryText],
      ["params", "msg", "content"],
      [:params, :msg, :content],
      ["params", "msg", "payload", "delta"],
      [:params, :msg, :payload, :delta],
      ["params", "msg", "payload", "textDelta"],
      [:params, :msg, :payload, :textDelta],
      ["params", "msg", "payload", "outputDelta"],
      [:params, :msg, :payload, :outputDelta],
      ["params", "msg", "payload", "text"],
      [:params, :msg, :payload, :text],
      ["params", "msg", "payload", "summaryText"],
      [:params, :msg, :payload, :summaryText],
      ["params", "msg", "payload", "content"],
      [:params, :msg, :payload, :content]
    ]
  end

  @spec reasoning_focus_paths() :: [[term()]]
  def reasoning_focus_paths do
    [
      ["params", "reason"],
      [:params, :reason],
      ["params", "summaryText"],
      [:params, :summaryText],
      ["params", "summary"],
      [:params, :summary],
      ["params", "text"],
      [:params, :text],
      ["params", "msg", "reason"],
      [:params, :msg, :reason],
      ["params", "msg", "summaryText"],
      [:params, :msg, :summaryText],
      ["params", "msg", "summary"],
      [:params, :msg, :summary],
      ["params", "msg", "text"],
      [:params, :msg, :text],
      ["params", "msg", "payload", "reason"],
      [:params, :msg, :payload, :reason],
      ["params", "msg", "payload", "summaryText"],
      [:params, :msg, :payload, :summaryText],
      ["params", "msg", "payload", "summary"],
      [:params, :msg, :payload, :summary],
      ["params", "msg", "payload", "text"],
      [:params, :msg, :payload, :text]
    ]
  end

  defp append_usage_part(parts, _label, value) when not is_integer(value), do: parts
  defp append_usage_part(parts, label, value), do: parts ++ ["#{label} #{Text.format_count(value)}"]

  defp format_rate_limit_bucket_summary(bucket) when is_map(bucket) do
    used_percent = Access.map_value(bucket, ["usedPercent", :usedPercent])
    window_mins = Access.map_value(bucket, ["windowDurationMins", :windowDurationMins])

    cond do
      is_number(used_percent) and is_integer(window_mins) ->
        "#{used_percent}% / #{window_mins}m"

      is_number(used_percent) ->
        "#{used_percent}% used"

      true ->
        nil
    end
  end

  defp format_rate_limit_bucket_summary(_bucket), do: nil
end
