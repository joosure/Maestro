defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Methods do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{
    Access,
    WrapperEvents
  }

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Methods.{
    Account,
    Items,
    Turns
  }

  @spec summary_text(String.t(), term()) :: String.t()
  def summary_text(
        method,
        payload
      )
      when method in [
             "thread/started",
             "turn/started",
             "turn/completed",
             "turn/failed",
             "turn/cancelled",
             "turn/diff/updated",
             "turn/plan/updated",
             "thread/tokenUsage/updated"
           ] do
    Turns.summary_text(method, payload)
  end

  def summary_text(
        method,
        payload
      )
      when method in [
             "item/started",
             "item/completed",
             "item/agentMessage/delta",
             "item/plan/delta",
             "item/reasoning/summaryTextDelta",
             "item/reasoning/summaryPartAdded",
             "item/reasoning/textDelta",
             "item/commandExecution/outputDelta",
             "item/fileChange/outputDelta",
             "item/commandExecution/requestApproval",
             "item/fileChange/requestApproval",
             "item/tool/requestUserInput",
             "tool/requestUserInput",
             "item/tool/call"
           ] do
    Items.summary_text(method, payload)
  end

  def summary_text(
        method,
        payload
      )
      when method in [
             "account/updated",
             "account/rateLimits/updated",
             "account/chatgptAuthTokens/refresh"
           ] do
    Account.summary_text(method, payload)
  end

  def summary_text(<<"codex/event/", suffix::binary>>, payload) do
    WrapperEvents.summary_text(suffix, payload)
  end

  def summary_text(method, payload) do
    msg_type =
      Access.map_path(payload, ["params", "msg", "type"]) ||
        Access.map_path(payload, [:params, :msg, :type])

    if is_binary(msg_type) do
      "#{method} (#{msg_type})"
    else
      method
    end
  end
end
