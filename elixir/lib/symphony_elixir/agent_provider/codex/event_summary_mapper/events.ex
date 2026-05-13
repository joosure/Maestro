defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Events do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{
    Access,
    Methods,
    Payload,
    Text
  }

  @spec summary_text(term(), term(), term()) :: String.t() | nil
  def summary_text(:session_started, _message, payload) do
    session_id = Access.map_value(payload, ["session_id", :session_id])

    if is_binary(session_id) do
      "session started (#{session_id})"
    else
      "session started"
    end
  end

  def summary_text(:turn_input_required, _message, _payload),
    do: "turn blocked: waiting for user input"

  def summary_text(:approval_auto_approved, message, payload) do
    method =
      Access.map_value(payload, ["method", :method]) ||
        Access.map_path(message, ["payload", "method"]) ||
        Access.map_path(message, [:payload, :method])

    decision = Access.map_value(message, ["decision", :decision])

    base =
      if is_binary(method) do
        "#{Methods.summary_text(method, payload)} (auto-approved)"
      else
        "approval request auto-approved"
      end

    if is_binary(decision), do: "#{base}: #{decision}", else: base
  end

  def summary_text(:tool_input_auto_answered, message, payload) do
    answer = Access.map_value(message, ["answer", :answer])

    base = "#{Methods.summary_text("item/tool/requestUserInput", payload)} (auto-answered)"

    if is_binary(answer), do: "#{base}: #{Text.inline_text(answer)}", else: base
  end

  def summary_text(:tool_call_completed, _message, payload),
    do: format_dynamic_tool_event("dynamic tool call completed", payload)

  def summary_text(:tool_call_failed, _message, payload),
    do: format_dynamic_tool_event("dynamic tool call failed", payload)

  def summary_text(:unsupported_tool_call, _message, payload),
    do: format_dynamic_tool_event("unsupported dynamic tool call rejected", payload)

  def summary_text(:stream_output, message, _payload),
    do: format_stream_event(message, "output")

  def summary_text(:stream_warning, message, _payload),
    do: format_stream_event(message, "warning")

  def summary_text(:turn_ended_with_error, message, _payload),
    do: "turn ended with error: #{Text.format_reason(message)}"

  def summary_text(:startup_failed, message, _payload),
    do: "startup failed: #{Text.format_reason(message)}"

  def summary_text(:turn_failed, _message, payload),
    do: Methods.summary_text("turn/failed", payload)

  def summary_text(:turn_cancelled, _message, _payload), do: "turn cancelled"
  def summary_text(:malformed, _message, _payload), do: "malformed JSON event from codex"
  def summary_text(_event, _message, _payload), do: nil

  defp format_dynamic_tool_event(base, payload) do
    case Payload.dynamic_tool_name(payload) do
      tool when is_binary(tool) ->
        trimmed = String.trim(tool)

        if trimmed == "" do
          base
        else
          "#{base} (#{trimmed})"
        end

      _ ->
        base
    end
  end

  defp format_stream_event(message, kind) when is_binary(kind) do
    stream_label = Access.map_value(message, ["stream_label", :stream_label])
    text = Access.map_value(message, ["payload", :payload])

    base =
      case stream_label do
        label when is_binary(label) and label != "" -> "#{label} #{kind}"
        _ -> "stream #{kind}"
      end

    if is_binary(text) and text != "" do
      "#{base}: #{Text.inline_text(text)}"
    else
      base
    end
  end
end
