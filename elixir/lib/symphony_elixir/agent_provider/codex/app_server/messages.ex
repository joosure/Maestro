defmodule SymphonyElixir.AgentProvider.Codex.AppServer.Messages do
  @moduledoc false

  alias SymphonyElixir.Observability.Redaction

  @spec emit((map() -> term()), atom(), map(), map()) :: term()
  def emit(on_message, event, details, metadata) when is_function(on_message, 1) do
    message =
      metadata
      |> Map.merge(sanitize_details(details))
      |> Map.put(:event, event)
      |> Map.put(:timestamp, DateTime.utc_now())

    on_message.(message)
  end

  defp sanitize_details(details) when is_map(details) do
    details
    |> maybe_put_payload_summary()
    |> Enum.reduce(%{}, fn
      {key, _value}, acc when key in [:raw, "raw"] ->
        acc

      {key, value}, acc when key in [:reason, "reason", :details, "details"] ->
        Map.put(acc, key, Redaction.summarize(value, 256))

      {key, value}, acc ->
        Map.put(acc, key, Redaction.redact(value))
    end)
  end

  defp maybe_put_payload_summary(details) when is_map(details) do
    if Map.has_key?(details, :payload_summary) or Map.has_key?(details, "payload_summary") do
      details
    else
      case message_summary_source(details) do
        nil -> details
        source -> Map.put(details, :payload_summary, Redaction.summarize(source, 256))
      end
    end
  end

  defp message_summary_source(details) when is_map(details) do
    Enum.find_value([:payload, "payload", :details, "details", :tool_result, "tool_result", :raw, "raw"], fn key ->
      Map.get(details, key)
    end)
  end
end
