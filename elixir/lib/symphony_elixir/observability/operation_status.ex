defmodule SymphonyElixir.Observability.OperationStatus do
  @moduledoc """
  Shared status labels for observability operation lifecycle events.
  """

  @started "started"
  @completed "completed"
  @failed "failed"
  @stopped "stopped"
  @prepared "prepared"

  @spec started() :: String.t()
  def started, do: @started

  @spec completed() :: String.t()
  def completed, do: @completed

  @spec failed() :: String.t()
  def failed, do: @failed

  @spec stopped() :: String.t()
  def stopped, do: @stopped

  @spec prepared() :: String.t()
  def prepared, do: @prepared
end
