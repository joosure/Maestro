defmodule SymphonyWorkerDaemon.Protocol.Features do
  @moduledoc """
  Stable feature identifiers advertised by the Worker Daemon health endpoint.
  """

  @health "health"
  @session_create "session_create"
  @session_status "session_status"
  @session_list "session_list"
  @session_events "session_events"
  @session_input "session_input"
  @session_stop "session_stop"
  @session_cleanup "session_cleanup"
  @dynamic_tool_bridge_proxy "dynamic_tool_bridge_proxy"
  @executable_policy "executable_policy"
  @timeout_policy "timeout_policy"
  @resource_budget "resource_budget"

  @supported [
    @health,
    @session_create,
    @session_status,
    @session_list,
    @session_events,
    @session_input,
    @session_stop,
    @session_cleanup,
    @dynamic_tool_bridge_proxy,
    @executable_policy,
    @timeout_policy,
    @resource_budget
  ]
  @session_required [
    @session_create,
    @session_status,
    @session_list,
    @session_input,
    @session_stop,
    @session_cleanup
  ]

  @spec health() :: String.t()
  def health, do: @health

  @spec session_create() :: String.t()
  def session_create, do: @session_create

  @spec session_status() :: String.t()
  def session_status, do: @session_status

  @spec session_list() :: String.t()
  def session_list, do: @session_list

  @spec session_events() :: String.t()
  def session_events, do: @session_events

  @spec session_input() :: String.t()
  def session_input, do: @session_input

  @spec session_stop() :: String.t()
  def session_stop, do: @session_stop

  @spec session_cleanup() :: String.t()
  def session_cleanup, do: @session_cleanup

  @spec dynamic_tool_bridge_proxy() :: String.t()
  def dynamic_tool_bridge_proxy, do: @dynamic_tool_bridge_proxy

  @spec executable_policy() :: String.t()
  def executable_policy, do: @executable_policy

  @spec timeout_policy() :: String.t()
  def timeout_policy, do: @timeout_policy

  @spec resource_budget() :: String.t()
  def resource_budget, do: @resource_budget

  @spec supported() :: [String.t()]
  def supported, do: @supported

  @spec session_required() :: [String.t()]
  def session_required, do: @session_required
end
