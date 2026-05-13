defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.WrapperEvents do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{
    Access,
    Payload,
    Summaries,
    Text
  }

  @spec summary_text(String.t(), term()) :: String.t()
  def summary_text("mcp_startup_update", payload) do
    server =
      Access.map_path(payload, ["params", "msg", "server"]) ||
        Access.map_path(payload, [:params, :msg, :server]) ||
        "mcp"

    state =
      Access.map_path(payload, ["params", "msg", "status", "state"]) ||
        Access.map_path(payload, [:params, :msg, :status, :state]) ||
        "updated"

    "mcp startup: #{server} #{state}"
  end

  def summary_text("mcp_startup_complete", _payload), do: "mcp startup complete"
  def summary_text("task_started", _payload), do: "task started"
  def summary_text("user_message", _payload), do: "user message received"

  def summary_text("item_started", payload) do
    case Payload.wrapper_payload_type(payload) do
      "token_count" -> summary_text("token_count", payload)
      type when is_binary(type) -> "item started (#{Text.format_item_type(type)})"
      _ -> "item started"
    end
  end

  def summary_text("item_completed", payload) do
    case Payload.wrapper_payload_type(payload) do
      "token_count" -> summary_text("token_count", payload)
      type when is_binary(type) -> "item completed (#{Text.format_item_type(type)})"
      _ -> "item completed"
    end
  end

  def summary_text("agent_message_delta", payload),
    do: Summaries.format_streaming_event("agent message streaming", payload)

  def summary_text("agent_message_content_delta", payload),
    do: Summaries.format_streaming_event("agent message content streaming", payload)

  def summary_text("agent_reasoning_delta", payload),
    do: Summaries.format_streaming_event("reasoning streaming", payload)

  def summary_text("reasoning_content_delta", payload),
    do: Summaries.format_streaming_event("reasoning content streaming", payload)

  def summary_text("agent_reasoning_section_break", _payload),
    do: "reasoning section break"

  def summary_text("agent_reasoning", payload),
    do: Summaries.format_reasoning_update(payload)

  def summary_text("turn_diff", _payload), do: "turn diff updated"
  def summary_text("exec_command_begin", payload), do: format_exec_command_begin(payload)
  def summary_text("exec_command_end", payload), do: format_exec_command_end(payload)
  def summary_text("exec_command_output_delta", _payload), do: "command output streaming"
  def summary_text("mcp_tool_call_begin", _payload), do: "mcp tool call started"
  def summary_text("mcp_tool_call_end", _payload), do: "mcp tool call completed"

  def summary_text("token_count", payload) do
    usage = Access.extract_first_path(payload, Summaries.token_usage_paths())

    case Summaries.format_usage_counts(usage) do
      nil -> "token count update"
      usage_text -> "token count update (#{usage_text})"
    end
  end

  def summary_text(other, payload) do
    msg_type =
      Access.map_path(payload, ["params", "msg", "type"]) ||
        Access.map_path(payload, [:params, :msg, :type])

    if is_binary(msg_type) do
      "#{other} (#{msg_type})"
    else
      other
    end
  end

  defp format_exec_command_begin(payload) do
    command =
      Access.map_path(payload, ["params", "msg", "command"]) ||
        Access.map_path(payload, [:params, :msg, :command]) ||
        Access.map_path(payload, ["params", "msg", "parsed_cmd"]) ||
        Access.map_path(payload, [:params, :msg, :parsed_cmd])

    command = Payload.normalize_command(command)

    if is_binary(command) do
      command
    else
      "command started"
    end
  end

  defp format_exec_command_end(payload) do
    exit_code =
      Access.map_path(payload, ["params", "msg", "exit_code"]) ||
        Access.map_path(payload, [:params, :msg, :exit_code]) ||
        Access.map_path(payload, ["params", "msg", "exitCode"]) ||
        Access.map_path(payload, [:params, :msg, :exitCode])

    if is_integer(exit_code) do
      "command completed (exit #{exit_code})"
    else
      "command completed"
    end
  end
end
