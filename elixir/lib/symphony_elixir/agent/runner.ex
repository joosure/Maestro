defmodule SymphonyElixir.Agent.Runner do
  @moduledoc """
  Executes a single issue in its workspace through the configured agent provider.
  """

  alias SymphonyElixir.Agent.Runner.Execution

  @spec run(map(), pid() | nil, keyword()) :: :ok
  def run(issue, update_recipient \\ nil, opts \\ []) do
    Execution.run(issue, update_recipient, opts)
  end
end
