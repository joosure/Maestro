defmodule SymphonyElixir.AgentProvider.MessagePresenter do
  @moduledoc """
  Provider-neutral rendering rules for agent message summaries.
  """

  alias SymphonyElixir.AgentProvider.EventSummary
  alias SymphonyElixir.Observability.Redaction

  @default_max_length 140

  @spec present(EventSummary.t() | term(), keyword()) :: String.t()
  def present(summary_or_message, opts \\ [])

  def present(%EventSummary{} = summary, opts) do
    max_length = Keyword.get(opts, :max_length, @default_max_length)

    summary
    |> summary_text()
    |> inline_text()
    |> Redaction.redact_string()
    |> truncate(max_length)
  end

  def present(message, opts) do
    message
    |> EventSummary.from_term()
    |> present(opts)
  end

  @spec inline_text(term()) :: String.t()
  def inline_text(text) when is_binary(text) do
    text
    |> String.replace("\n", " ")
    |> String.replace(~r/\s+/, " ")
    |> sanitize_ansi_and_control_bytes()
    |> String.trim()
  end

  def inline_text(other), do: other |> to_string() |> inline_text()

  @spec sanitize_ansi_and_control_bytes(String.t()) :: String.t()
  def sanitize_ansi_and_control_bytes(value) when is_binary(value) do
    value
    |> String.replace(~r/\x1B\[[0-9;]*[A-Za-z]/, "")
    |> String.replace(~r/\x1B./, "")
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
  end

  @spec truncate(String.t(), pos_integer()) :: String.t()
  def truncate(value, max) when is_binary(value) and is_integer(max) and max > 0 and byte_size(value) > max do
    value |> String.slice(0, max) |> Kernel.<>("...")
  end

  def truncate(value, _max), do: value

  defp summary_text(%EventSummary{text: text}) when is_binary(text) and text != "", do: text
  defp summary_text(%EventSummary{detail: detail}) when is_binary(detail) and detail != "", do: detail
  defp summary_text(_summary), do: "agent update"
end
