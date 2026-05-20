defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.EventSummaryMapper do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.EventSummary
  alias SymphonyElixir.AgentProvider.EventSummaryMapper.{Access, Text}
  alias SymphonyElixir.AgentProvider.Kinds

  @provider_kind Kinds.codebuddy_code()

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
  defp summary_text(:turn_started, payload), do: "turn started: #{Text.inline_text(Access.map_value(payload, :title) || "agent turn")}"
  defp summary_text(:turn_completed, _payload), do: "turn completed"
  defp summary_text(:turn_ended_with_error, payload), do: "turn failed: #{Text.format_reason(Access.map_value(payload, :reason) || payload)}"
  defp summary_text(:turn_input_required, _payload), do: "turn requires input"
  defp summary_text(:notification, payload), do: notification_summary(payload)
  defp summary_text(:tool_update, payload), do: tool_summary(payload)
  defp summary_text("message.part.updated", payload), do: part_summary(part_from_payload(payload))
  defp summary_text(event, _payload) when is_binary(event) and event != "", do: event
  defp summary_text(event, _payload) when is_atom(event), do: Atom.to_string(event)
  defp summary_text(_event, payload), do: Text.default_summary(payload)

  defp notification_summary(payload) do
    payload
    |> Access.path_value([:payload, "method"])
    |> case do
      "session/update" -> Access.path_value(payload, [:payload, "params", "update", "sessionUpdate"]) || "session/update"
      method when is_binary(method) -> method
      _method -> "provider notification"
    end
  end

  defp part_summary(%{} = part) do
    case Access.map_value(part, :type) do
      "text" -> streaming_summary("agent message streaming", Access.map_value(part, :text))
      "reasoning" -> streaming_summary("reasoning update", Access.map_value(part, :text))
      "tool" -> tool_summary(part)
      type when is_binary(type) and type != "" -> "#{Text.format_type(type)} update"
      _type -> "message part updated"
    end
  end

  defp part_summary(_part), do: "message part updated"

  defp tool_summary(payload) do
    tool = Access.map_value(payload, :tool) || Access.map_value(payload, :name)
    status = Access.path_value(payload, [:state, :status]) || Access.map_value(payload, :status)

    cond do
      is_binary(tool) and is_binary(status) -> "tool #{status} (#{Text.inline_text(tool)})"
      is_binary(tool) -> "tool update (#{Text.inline_text(tool)})"
      true -> "tool update"
    end
  end

  defp streaming_summary(prefix, value) when is_binary(value) and value != "", do: "#{prefix}: #{Text.inline_text(value)}"
  defp streaming_summary(prefix, _value), do: prefix

  defp category_for(event, _payload) when event in [:turn_started, :turn_completed, :turn_ended_with_error], do: :turn
  defp category_for(:turn_input_required, _payload), do: :approval
  defp category_for(:tool_update, _payload), do: :tool
  defp category_for("message.part.updated", %{} = payload), do: part_category(part_from_payload(payload))
  defp category_for(_event, _payload), do: :message

  defp part_category(%{} = part) do
    case Access.map_value(part, :type) do
      "tool" -> :tool
      _type -> :message
    end
  end

  defp part_category(_part), do: :message

  defp severity_for(event, _payload) when event in [:turn_ended_with_error, :turn_input_required], do: :error
  defp severity_for(_event, _payload), do: :info

  defp event_value(%{} = message), do: Access.map_value(message, :event)
  defp event_value(_message), do: nil

  defp payload_value(nil), do: nil

  defp payload_value(%{} = message) do
    cond do
      nested = Access.map_value(message, :message) -> nested
      Access.map_value(message, :event) -> message
      payload = Access.map_value(message, :payload) -> payload
      true -> message
    end
  end

  defp payload_value(message), do: message

  defp part_from_payload(payload) do
    Access.path_value(payload, [:payload, :payload, :properties, :part]) ||
      Access.path_value(payload, [:payload, :properties, :part]) ||
      Access.path_value(payload, [:properties, :part]) ||
      Access.map_value(payload, :part)
  end
end
