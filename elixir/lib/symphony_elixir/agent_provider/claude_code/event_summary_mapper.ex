defmodule SymphonyElixir.AgentProvider.ClaudeCode.EventSummaryMapper do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.EventSummary
  alias SymphonyElixir.AgentProvider.EventSummaryMapper.{Access, Text}

  @provider_kind "claude_code"

  @spec summarize(term()) :: EventSummary.t()
  def summarize(message) do
    event = event_value(message)
    payload = payload_value(message)

    EventSummary.new(summary_text(event, payload),
      provider_kind: @provider_kind,
      event: event,
      category: category_for(event, payload),
      severity: severity_for(event, payload),
      payload: payload,
      raw: message
    )
  end

  defp summary_text(nil, nil), do: "no agent message yet"

  defp summary_text(:turn_started, payload) do
    case Access.map_value(payload, :title) do
      title when is_binary(title) and title != "" -> "turn started: #{Text.inline_text(title)}"
      _ -> "turn started"
    end
  end

  defp summary_text(:turn_completed, payload) do
    case Text.format_usage(Access.map_value(payload, :usage)) do
      nil -> "turn completed"
      usage -> "turn completed (#{usage})"
    end
  end

  defp summary_text(:turn_ended_with_error, payload),
    do: "turn failed: #{format_reason(Access.map_value(payload, :reason) || payload)}"

  defp summary_text("message.part.updated", payload) do
    payload
    |> part_from_payload()
    |> part_summary()
  end

  defp summary_text(event, payload) when is_binary(event) and event != "" do
    case Text.format_usage(Access.map_value(payload, :usage)) do
      nil -> event
      usage -> "#{event} (#{usage})"
    end
  end

  defp summary_text(_event, payload), do: Text.default_summary(payload)

  defp part_summary(%{} = part) do
    case Access.map_value(part, :type) do
      "text" ->
        streaming_summary("agent message streaming", Access.map_value(part, :text))

      type when type in ["reasoning", "thinking"] ->
        streaming_summary("reasoning update", Access.map_value(part, :text))

      "tool" ->
        tool = Access.map_value(part, :tool) || Access.map_value(part, :name)
        status = Access.map_value(Access.map_value(part, :state), :status)

        cond do
          is_binary(tool) and is_binary(status) -> "tool #{status} (#{Text.inline_text(tool)})"
          is_binary(tool) -> "tool running (#{Text.inline_text(tool)})"
          true -> "tool running"
        end

      type when is_binary(type) and type != "" ->
        "#{Text.format_type(type)} update"

      _ ->
        "message part updated"
    end
  end

  defp part_summary(_part), do: "message part updated"

  defp streaming_summary(prefix, value) when is_binary(value) and value != "" do
    "#{prefix}: #{Text.inline_text(value)}"
  end

  defp streaming_summary(prefix, _value), do: prefix

  defp category_for(event, _payload) when event in [:turn_started, :turn_completed, :turn_ended_with_error], do: :turn
  defp category_for("message.part.updated", %{} = payload), do: part_category(part_from_payload(payload))
  defp category_for(_event, _payload), do: :message

  defp part_category(%{} = part) do
    case Access.map_value(part, :type) do
      "tool" -> :tool
      _ -> :message
    end
  end

  defp part_category(_part), do: :message

  defp severity_for(:turn_ended_with_error, _payload), do: :error
  defp severity_for(_event, _payload), do: :info

  defp event_value(%{} = message), do: Access.map_value(message, :event)
  defp event_value(_message), do: nil

  defp payload_value(nil), do: nil

  defp payload_value(%{} = message) do
    cond do
      nested = Access.map_value(message, :message) ->
        nested

      Access.map_value(message, :event) ->
        message

      payload = Access.map_value(message, :payload) ->
        payload

      true ->
        message
    end
  end

  defp payload_value(message), do: message

  defp part_from_payload(payload) do
    Access.path_value(payload, [:payload, :payload, :properties, :part]) ||
      Access.path_value(payload, [:payload, :properties, :part]) ||
      Access.path_value(payload, [:properties, :part]) ||
      Access.map_value(payload, :part)
  end

  defp format_reason({:claude_result_error, %{} = payload}) do
    Access.path_value(payload, [:error, :message]) ||
      Access.path_value(payload, [:result, :message]) ||
      Access.map_value(payload, :message) ||
      Text.default_summary(payload)
  end

  defp format_reason(reason), do: Text.format_reason(reason)
end
