defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Methods.Items do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{
    Access,
    Payload,
    Summaries,
    Text
  }

  @spec summary_text(String.t(), term()) :: String.t()
  def summary_text("item/started", payload), do: format_item_lifecycle("started", payload)
  def summary_text("item/completed", payload), do: format_item_lifecycle("completed", payload)

  def summary_text("item/agentMessage/delta", payload),
    do: Summaries.format_streaming_event("agent message streaming", payload)

  def summary_text("item/plan/delta", payload),
    do: Summaries.format_streaming_event("plan streaming", payload)

  def summary_text("item/reasoning/summaryTextDelta", payload),
    do: Summaries.format_streaming_event("reasoning summary streaming", payload)

  def summary_text("item/reasoning/summaryPartAdded", payload),
    do: Summaries.format_streaming_event("reasoning summary section added", payload)

  def summary_text("item/reasoning/textDelta", payload),
    do: Summaries.format_streaming_event("reasoning text streaming", payload)

  def summary_text("item/commandExecution/outputDelta", payload),
    do: Summaries.format_streaming_event("command output streaming", payload)

  def summary_text("item/fileChange/outputDelta", payload),
    do: Summaries.format_streaming_event("file change output streaming", payload)

  def summary_text("item/commandExecution/requestApproval", payload) do
    command = Payload.extract_command(payload)

    if is_binary(command) do
      "command approval requested (#{command})"
    else
      "command approval requested"
    end
  end

  def summary_text("item/fileChange/requestApproval", payload) do
    change_count =
      Access.map_path(payload, ["params", "fileChangeCount"]) ||
        Access.map_path(payload, ["params", "changeCount"])

    if is_integer(change_count) and change_count > 0 do
      "file change approval requested (#{change_count} files)"
    else
      "file change approval requested"
    end
  end

  def summary_text("item/tool/requestUserInput", payload) do
    question =
      Access.map_path(payload, ["params", "question"]) ||
        Access.map_path(payload, ["params", "prompt"]) ||
        Access.map_path(payload, [:params, :question]) ||
        Access.map_path(payload, [:params, :prompt])

    if is_binary(question) and String.trim(question) != "" do
      "tool requires user input: #{Text.inline_text(question)}"
    else
      "tool requires user input"
    end
  end

  def summary_text("tool/requestUserInput", payload),
    do: summary_text("item/tool/requestUserInput", payload)

  def summary_text("item/tool/call", payload) do
    tool = Payload.dynamic_tool_name(payload)

    if is_binary(tool) and String.trim(tool) != "" do
      "dynamic tool call requested (#{tool})"
    else
      "dynamic tool call requested"
    end
  end

  defp format_item_lifecycle(state, payload) do
    item =
      Access.map_path(payload, ["params", "item"]) ||
        Access.map_path(payload, [:params, :item]) ||
        %{}

    item_type = item |> Access.map_value(["type", :type]) |> Text.format_item_type()
    item_status = Access.map_value(item, ["status", :status])
    item_id = Access.map_value(item, ["id", :id])

    details =
      []
      |> Text.append_if_present(Text.short_id(item_id))
      |> Text.append_if_present(Text.format_status(item_status))

    detail_suffix = if details == [], do: "", else: " (#{Enum.join(details, ", ")})"
    "item #{state}: #{item_type}#{detail_suffix}"
  end
end
