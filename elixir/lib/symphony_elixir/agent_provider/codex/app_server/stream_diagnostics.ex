defmodule SymphonyElixir.AgentProvider.Codex.AppServer.StreamDiagnostics do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.AppServer.EventFields
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.Redaction

  @max_stream_log_bytes 1_000
  @warning_pattern ~r/\b(error|warn|warning|failed|fatal|panic|exception)\b/i

  @spec log_response_line(term(), String.t()) :: :ok | nil
  def log_response_line(data, stream_label) do
    text = sanitized_text(data)

    if text != "" do
      ObsLogger.text(
        :debug,
        "codex_stream_output",
        EventFields.turn(nil, %{
          event: :codex_stream_output,
          stream_label: stream_label,
          payload_summary: text
        })
      )
    end
  end

  @spec log_turn_line(term(), String.t(), map()) ::
          {:stream_output | :stream_warning, String.t(), String.t()} | nil
  def log_turn_line(data, stream_label, turn_context) do
    text = sanitized_text(data)

    if text != "" do
      if String.match?(text, @warning_pattern) do
        ObsLogger.emit(
          :warning,
          :codex_stream_warning,
          EventFields.turn(turn_context, %{
            stream_label: stream_label,
            payload_summary: text
          })
        )

        {:stream_warning, text, stream_label}
      else
        ObsLogger.text(
          :debug,
          "codex_stream_output",
          EventFields.turn(turn_context, %{
            event: :codex_stream_output,
            stream_label: stream_label,
            payload_summary: text
          })
        )

        {:stream_output, text, stream_label}
      end
    end
  end

  @spec protocol_message_candidate?(term()) :: boolean()
  def protocol_message_candidate?(data) do
    data
    |> to_string()
    |> String.trim_leading()
    |> String.starts_with?("{")
  end

  defp sanitized_text(data) do
    data
    |> to_string()
    |> Redaction.redact_string()
    |> String.trim()
    |> String.slice(0, @max_stream_log_bytes)
  end
end
