defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Methods.Account do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.{Access, Summaries}

  @spec summary_text(String.t(), term()) :: String.t()
  def summary_text("account/updated", payload) do
    auth_mode =
      Access.map_path(payload, ["params", "authMode"]) ||
        Access.map_path(payload, [:params, :authMode]) ||
        "unknown"

    "account updated (auth #{auth_mode})"
  end

  def summary_text("account/rateLimits/updated", payload) do
    rate_limits =
      Access.map_path(payload, ["params", "rateLimits"]) ||
        Access.map_path(payload, [:params, :rateLimits])

    "rate limits updated: #{Summaries.format_rate_limits_summary(rate_limits)}"
  end

  def summary_text("account/chatgptAuthTokens/refresh", _payload),
    do: "account auth token refresh requested"
end
