defmodule SymphonyElixir.Observability.OperationName do
  @moduledoc """
  Shared operation labels for observability lifecycle events.
  """

  @run_turn "run_turn"

  @spec run_turn() :: String.t()
  def run_turn, do: @run_turn
end
