defmodule SymphonyWorkerDaemon.Session.Status do
  @moduledoc false

  @running "running"
  @exited "exited"
  @failed "failed"
  @cleaned "cleaned"
  @stopped "stopped"
  @lost "lost"

  @terminal_statuses [
    @exited,
    @failed,
    @lost,
    @cleaned,
    @stopped
  ]

  @successful_terminal_statuses [
    @exited,
    @cleaned,
    @stopped
  ]

  @spec running() :: String.t()
  def running, do: @running

  @spec exited() :: String.t()
  def exited, do: @exited

  @spec failed() :: String.t()
  def failed, do: @failed

  @spec cleaned() :: String.t()
  def cleaned, do: @cleaned

  @spec stopped() :: String.t()
  def stopped, do: @stopped

  @spec lost() :: String.t()
  def lost, do: @lost

  @spec terminal_statuses() :: [String.t()]
  def terminal_statuses, do: @terminal_statuses

  @spec successful_terminal_statuses() :: [String.t()]
  def successful_terminal_statuses, do: @successful_terminal_statuses

  @spec terminal?(term()) :: boolean()
  def terminal?(status) when is_binary(status), do: status in @terminal_statuses
  def terminal?(_status), do: false

  @spec successful_terminal?(term()) :: boolean()
  def successful_terminal?(status) when is_binary(status), do: status in @successful_terminal_statuses
  def successful_terminal?(_status), do: false

  @spec exit_status_name(integer()) :: String.t()
  def exit_status_name(0), do: @exited
  def exit_status_name(_status), do: @failed

  @spec put_stop_reason(map(), term()) :: map()
  def put_stop_reason(state, nil), do: state
  def put_stop_reason(state, reason) when is_binary(reason), do: Map.put(state, :stop_reason, reason)
  def put_stop_reason(state, reason) when is_atom(reason), do: Map.put(state, :stop_reason, Atom.to_string(reason))
  def put_stop_reason(state, reason), do: Map.put(state, :stop_reason, inspect(reason))
end
