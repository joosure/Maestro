defmodule SymphonyElixir.Agent do
  @moduledoc """
  Provider-neutral Agent runtime for Symphony work items.
  """

  alias SymphonyElixir.Agent.Runner

  @spec run(map(), pid() | nil, keyword()) :: :ok
  defdelegate run(issue, update_recipient \\ nil, opts \\ []), to: Runner
end
