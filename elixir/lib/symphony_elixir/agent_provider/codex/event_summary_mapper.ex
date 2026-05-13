defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventMapper
  alias SymphonyElixir.AgentProvider.EventSummary

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{
    Access,
    Events,
    Methods,
    Payload,
    Text
  }

  @spec summarize(term()) :: EventSummary.t()
  def summarize(message) do
    message
    |> EventMapper.map_message()
    |> summarize_event()
  end

  @spec summary_text(term()) :: String.t()
  def summary_text(nil), do: "no agent message yet"

  def summary_text(%{event: event, message: message}) do
    payload = Payload.unwrap_message_payload(message)

    Events.summary_text(event, message, payload) || summarize_payload(payload)
  end

  def summary_text(%{message: message}) do
    message
    |> Payload.unwrap_message_payload()
    |> summarize_payload()
  end

  def summary_text(message) do
    message
    |> Payload.unwrap_message_payload()
    |> summarize_payload()
  end

  defp summarize_event(mapped_event) do
    event = Map.get(mapped_event, :event)
    payload = Map.get(mapped_event, :payload)
    raw = Map.get(mapped_event, :raw)

    EventSummary.new(
      Events.summary_text(event, raw, payload) || summarize_payload(payload),
      event_summary_opts(mapped_event)
    )
  end

  defp event_summary_opts(mapped_event) do
    [
      provider_kind: Map.get(mapped_event, :agent_provider_kind),
      event: Map.get(mapped_event, :event),
      category: category_for(Map.get(mapped_event, :event), Map.get(mapped_event, :payload)),
      severity: severity_for(Map.get(mapped_event, :event)),
      payload: Map.get(mapped_event, :payload),
      raw: Map.get(mapped_event, :raw)
    ]
  end

  defp summarize_payload(%{} = payload) do
    case Access.map_value(payload, ["method", :method]) do
      method when is_binary(method) ->
        Methods.summary_text(method, payload)

      _ ->
        cond do
          is_binary(Access.map_value(payload, ["session_id", :session_id])) ->
            "session started (#{Access.map_value(payload, ["session_id", :session_id])})"

          match?(%{"error" => _}, payload) ->
            "error: #{Text.format_error_value(Map.get(payload, "error"))}"

          true ->
            payload
            |> inspect(pretty: true, limit: 30)
            |> String.replace("\n", " ")
            |> Text.sanitize_ansi_and_control_bytes()
            |> String.trim()
        end
    end
  end

  defp summarize_payload(payload) when is_binary(payload) do
    payload
    |> String.replace("\n", " ")
    |> Text.sanitize_ansi_and_control_bytes()
    |> String.trim()
  end

  defp summarize_payload(payload) do
    payload
    |> inspect(pretty: true, limit: 20)
    |> String.replace("\n", " ")
    |> Text.sanitize_ansi_and_control_bytes()
    |> String.trim()
  end

  defp category_for(:session_started, _payload), do: :session
  defp category_for(:turn_failed, _payload), do: :turn
  defp category_for(:turn_cancelled, _payload), do: :turn
  defp category_for(:turn_ended_with_error, _payload), do: :turn
  defp category_for(:approval_auto_approved, _payload), do: :approval
  defp category_for(:tool_input_auto_answered, _payload), do: :tool
  defp category_for(:tool_call_completed, _payload), do: :tool
  defp category_for(:tool_call_failed, _payload), do: :tool
  defp category_for(:unsupported_tool_call, _payload), do: :tool
  defp category_for(:stream_output, _payload), do: :stream
  defp category_for(:stream_warning, _payload), do: :stream

  defp category_for(_event, %{} = payload) do
    case Access.map_value(payload, ["method", :method]) do
      <<"codex/event/token_count">> -> :usage
      <<"codex/event/", _rest::binary>> -> :message
      <<"turn/", _rest::binary>> -> :turn
      <<"thread/", _rest::binary>> -> :session
      <<"item/tool/", _rest::binary>> -> :tool
      <<"tool/", _rest::binary>> -> :tool
      _ -> :message
    end
  end

  defp category_for(_event, _payload), do: :message

  defp severity_for(event) when event in [:turn_failed, :tool_call_failed, :startup_failed, :turn_ended_with_error],
    do: :error

  defp severity_for(event) when event in [:stream_warning, :unsupported_tool_call], do: :warning
  defp severity_for(_event), do: :info
end
