defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Methods.Turns do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{Access, Summaries}

  @spec summary_text(String.t(), term()) :: String.t()
  def summary_text("thread/started", payload) do
    thread_id =
      Access.map_path(payload, ["params", "thread", "id"]) ||
        Access.map_path(payload, [:params, :thread, :id])

    if is_binary(thread_id) do
      "thread started (#{thread_id})"
    else
      "thread started"
    end
  end

  def summary_text("turn/started", payload) do
    turn_id =
      Access.map_path(payload, ["params", "turn", "id"]) ||
        Access.map_path(payload, [:params, :turn, :id])

    if is_binary(turn_id) do
      "turn started (#{turn_id})"
    else
      "turn started"
    end
  end

  def summary_text("turn/completed", payload) do
    status =
      Access.map_path(payload, ["params", "turn", "status"]) ||
        Access.map_path(payload, [:params, :turn, :status]) ||
        "completed"

    usage =
      Access.map_path(payload, ["params", "usage"]) ||
        Access.map_path(payload, [:params, :usage]) ||
        Access.map_path(payload, ["params", "tokenUsage"]) ||
        Access.map_path(payload, [:params, :tokenUsage]) ||
        Access.map_value(payload, ["usage", :usage])

    usage_suffix =
      case Summaries.format_usage_counts(usage) do
        nil -> ""
        usage_text -> " (#{usage_text})"
      end

    "turn completed (#{status})#{usage_suffix}"
  end

  def summary_text("turn/failed", payload) do
    error_message =
      Access.map_path(payload, ["params", "error", "message"]) ||
        Access.map_path(payload, [:params, :error, :message])

    if is_binary(error_message), do: "turn failed: #{error_message}", else: "turn failed"
  end

  def summary_text("turn/cancelled", _payload), do: "turn cancelled"

  def summary_text("turn/diff/updated", payload) do
    diff =
      Access.map_path(payload, ["params", "diff"]) ||
        Access.map_path(payload, [:params, :diff]) ||
        ""

    if is_binary(diff) and diff != "" do
      line_count = diff |> String.split("\n", trim: true) |> length()
      "turn diff updated (#{line_count} lines)"
    else
      "turn diff updated"
    end
  end

  def summary_text("turn/plan/updated", payload) do
    plan_entries =
      Access.map_path(payload, ["params", "plan"]) ||
        Access.map_path(payload, [:params, :plan]) ||
        Access.map_path(payload, ["params", "steps"]) ||
        Access.map_path(payload, [:params, :steps]) ||
        Access.map_path(payload, ["params", "items"]) ||
        Access.map_path(payload, [:params, :items]) ||
        []

    if is_list(plan_entries) do
      "plan updated (#{length(plan_entries)} steps)"
    else
      "plan updated"
    end
  end

  def summary_text("thread/tokenUsage/updated", payload) do
    usage =
      Access.map_path(payload, ["params", "tokenUsage", "total"]) ||
        Access.map_path(payload, [:params, :tokenUsage, :total]) ||
        Access.map_value(payload, ["usage", :usage])

    case Summaries.format_usage_counts(usage) do
      nil -> "thread token usage updated"
      usage_text -> "thread token usage updated (#{usage_text})"
    end
  end
end
