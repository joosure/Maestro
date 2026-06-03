defmodule SymphonyElixir.AgentProvider.OpenCode.EventSummaryMapper do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.EventSummary
  alias SymphonyElixir.AgentProvider.EventSummaryMapper.{Access, Text}
  alias SymphonyElixir.AgentProvider.Kinds

  @provider_kind Kinds.opencode()
  @part_category_by_type %{
    "tool" => :tool,
    "step-finish" => :usage
  }

  @spec summarize(term()) :: EventSummary.t()
  def summarize(message) do
    event = event_value(message)
    payload = payload_value(message)
    properties = event_properties(payload)

    EventSummary.new(summary_text(event, payload, properties),
      provider_kind: @provider_kind,
      event: event,
      category: category_for(event, properties),
      severity: severity_for(event, properties),
      payload: payload,
      raw: message
    )
  end

  defp summary_text(nil, nil, _properties), do: "no agent message yet"

  defp summary_text(:turn_started, payload, _properties) do
    case Access.map_value(payload, :title) do
      title when is_binary(title) and title != "" -> "turn started: #{Text.inline_text(title)}"
      _ -> "turn started"
    end
  end

  defp summary_text(:turn_completed, payload, _properties) do
    case Text.format_usage(Access.map_value(payload, :usage)) do
      nil -> "turn completed"
      usage -> "turn completed (#{usage})"
    end
  end

  defp summary_text(:turn_ended_with_error, payload, _properties),
    do: "turn failed: #{Text.format_reason(Access.map_value(payload, :reason) || payload)}"

  defp summary_text("message.part.updated", _payload, %{} = properties) do
    properties
    |> Access.map_value(:part)
    |> part_summary()
  end

  defp summary_text("message.updated", _payload, %{} = properties) do
    info = Access.map_value(properties, :info) || properties

    cond do
      error = Access.map_value(info, :error) ->
        "message failed: #{Text.format_reason(error)}"

      usage = Access.map_value(info, :tokens) ->
        case Text.format_usage(usage) do
          nil -> "message updated"
          usage_text -> "message updated (#{usage_text})"
        end

      true ->
        "message updated"
    end
  end

  defp summary_text("permission.asked", _payload, %{} = properties) do
    permission = Access.map_value(properties, :permission) || "permission"
    patterns = Access.map_value(properties, :patterns)

    case Text.format_patterns(patterns) do
      nil -> "permission requested (#{Text.inline_text(permission)})"
      pattern_text -> "permission requested (#{Text.inline_text(permission)}: #{pattern_text})"
    end
  end

  defp summary_text("question.asked", _payload, %{} = properties) do
    question =
      Access.map_value(properties, :question) ||
        Access.map_value(properties, :prompt) ||
        Access.map_value(properties, :message)

    if is_binary(question) and String.trim(question) != "" do
      "user input requested: #{Text.inline_text(question)}"
    else
      "user input requested"
    end
  end

  defp summary_text("session.error", _payload, %{} = properties),
    do: "session error: #{Text.format_reason(Access.map_value(properties, :error) || properties)}"

  defp summary_text(event, payload, _properties) when is_binary(event) and event != "" do
    case Text.format_usage(Access.map_value(payload, :usage)) do
      nil -> event
      usage -> "#{event} (#{usage})"
    end
  end

  defp summary_text(_event, payload, _properties), do: Text.default_summary(payload)

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
          is_binary(tool) -> "tool update (#{Text.inline_text(tool)})"
          true -> "tool update"
        end

      "step-finish" ->
        case Text.format_usage(Access.map_value(part, :tokens)) do
          nil -> "step completed"
          usage -> "step completed (#{usage})"
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

  defp category_for(event, _properties) when event in [:turn_started, :turn_completed, :turn_ended_with_error], do: :turn
  defp category_for("permission.asked", _properties), do: :approval
  defp category_for("question.asked", _properties), do: :tool
  defp category_for("session.error", _properties), do: :error
  defp category_for("message.updated", %{} = properties), do: message_updated_category(properties)
  defp category_for("message.part.updated", %{} = properties), do: part_category(Access.map_value(properties, :part))
  defp category_for(_event, _properties), do: :message

  defp message_updated_category(%{} = properties) do
    info = Access.map_value(properties, :info) || properties

    cond do
      Access.map_value(info, :error) -> :error
      Access.map_value(info, :tokens) -> :usage
      true -> :message
    end
  end

  defp part_category(%{} = part) do
    Map.get(@part_category_by_type, Access.map_value(part, :type), :message)
  end

  defp part_category(_part), do: :message

  defp severity_for(:turn_ended_with_error, _properties), do: :error
  defp severity_for("session.error", _properties), do: :error
  defp severity_for("message.updated", %{} = properties), do: if(message_updated_category(properties) == :error, do: :error, else: :info)
  defp severity_for("question.asked", _properties), do: :warning
  defp severity_for(_event, _properties), do: :info

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

  defp event_properties(payload) do
    Access.path_value(payload, [:payload, :payload, :payload, :properties]) ||
      Access.path_value(payload, [:payload, :payload, :properties]) ||
      Access.path_value(payload, [:payload, :properties]) ||
      Access.path_value(payload, [:properties]) ||
      %{}
  end
end
