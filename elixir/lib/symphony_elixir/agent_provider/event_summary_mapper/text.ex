defmodule SymphonyElixir.AgentProvider.EventSummaryMapper.Text do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.EventSummaryMapper.Access
  alias SymphonyElixir.AgentProvider.MessagePresenter
  alias SymphonyElixir.Observability.Redaction

  @spec format_reason(term()) :: String.t()
  def format_reason({kind, %{} = details}) when is_atom(kind) do
    details
    |> reason_value()
    |> reason_text(details)
  end

  def format_reason(reason) when is_binary(reason), do: inline_text(reason)

  def format_reason(%{} = reason) do
    reason
    |> reason_value()
    |> reason_text(reason)
  end

  def format_reason(reason), do: default_summary(reason)

  @spec format_patterns(term()) :: String.t() | nil
  def format_patterns(patterns) when is_list(patterns) do
    patterns
    |> Enum.filter(&is_binary/1)
    |> Enum.take(3)
    |> case do
      [] -> nil
      values -> Enum.map_join(values, ", ", &inline_text/1)
    end
  end

  def format_patterns(_patterns), do: nil

  @spec format_usage(term()) :: String.t() | nil
  def format_usage(nil), do: nil

  def format_usage(%{} = usage) do
    [
      usage_part("in", token_value(usage, [:input, :input_tokens])),
      usage_part("out", token_value(usage, [:output, :output_tokens])),
      usage_part("reasoning", token_value(usage, [:reasoning, :reasoning_tokens])),
      usage_part("total", token_value(usage, [:total, :total_tokens]))
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  def format_usage(_usage), do: nil

  @spec default_summary(term()) :: String.t()
  def default_summary(nil), do: "no agent message yet"
  def default_summary(value) when is_binary(value), do: inline_text(value)

  def default_summary(value) do
    value
    |> Redaction.summarize(256)
    |> inline_text()
  end

  @spec inline_text(term()) :: String.t()
  def inline_text(value), do: MessagePresenter.inline_text(value)

  @spec format_type(String.t()) :: String.t()
  def format_type(type) when is_binary(type) do
    type
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.replace(["_", "-", "."], " ")
    |> String.downcase()
  end

  defp usage_part(_label, nil), do: nil
  defp usage_part(_label, 0), do: nil
  defp usage_part(label, value) when is_integer(value), do: "#{label} #{format_count(value)}"

  defp token_value(usage, keys) do
    Enum.find_value(keys, fn key ->
      case Access.map_value(usage, key) do
        value when is_integer(value) and value >= 0 -> value
        value when is_binary(value) -> parse_non_negative_integer(value)
        _ -> nil
      end
    end)
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _ -> nil
    end
  end

  defp reason_value(%{} = details) do
    Access.map_value(details, :message) ||
      Access.map_value(details, :cause) ||
      Access.map_value(details, :error)
  end

  defp reason_text(nil, default_text), do: default_summary(default_text)
  defp reason_text(value, _default) when is_binary(value), do: inline_text(value)
  defp reason_text(value, _default), do: default_summary(value)

  defp format_count(value) when value >= 1_000_000, do: "#{Float.round(value / 1_000_000, 1)}m"
  defp format_count(value) when value >= 1_000, do: "#{Float.round(value / 1_000, 1)}k"
  defp format_count(value), do: Integer.to_string(value)
end
