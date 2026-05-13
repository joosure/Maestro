defmodule SymphonyElixir do
  @moduledoc """
  Library entrypoint for embedding the Symphony orchestrator in the current
  BEAM node.
  """

  @doc """
  Start the orchestrator in the current BEAM node.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    SymphonyElixir.Orchestrator.start_link(opts)
  end
end
