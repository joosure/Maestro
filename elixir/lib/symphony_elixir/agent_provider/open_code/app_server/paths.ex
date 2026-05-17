defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.Paths do
  @moduledoc """
  OpenCode app-server HTTP path contract.
  """

  @session "/session"
  @global_health "/global/health"
  @global_event "/global/event"

  @spec session() :: String.t()
  def session, do: @session

  @spec session_message(String.t()) :: String.t()
  def session_message(session_id) when is_binary(session_id), do: @session <> "/" <> session_id <> "/message"

  @spec session_abort(String.t()) :: String.t()
  def session_abort(session_id) when is_binary(session_id), do: @session <> "/" <> session_id <> "/abort"

  @spec global_health() :: String.t()
  def global_health, do: @global_health

  @spec global_event() :: String.t()
  def global_event, do: @global_event
end
