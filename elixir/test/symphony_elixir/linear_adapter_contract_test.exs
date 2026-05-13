defmodule SymphonyElixir.LinearAdapterContractTest do
  use ExUnit.Case, async: false

  use SymphonyElixir.TrackerAdapterContract,
    adapter: SymphonyElixir.Tracker.Linear.Adapter,
    config: %SymphonyElixir.Tracker.Config{
      kind: "linear",
      endpoint: "https://api.linear.app/graphql",
      auth: %{},
      provider: %{},
      lifecycle: %{
        "active_states" => ["Todo"],
        "terminal_states" => ["Done"]
      }
    }
end
