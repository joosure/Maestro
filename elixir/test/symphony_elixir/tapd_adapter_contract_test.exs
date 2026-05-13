defmodule SymphonyElixir.TapdAdapterContractTest do
  use ExUnit.Case, async: false

  use SymphonyElixir.TrackerAdapterContract,
    adapter: SymphonyElixir.Tracker.Tapd.Adapter,
    config: %SymphonyElixir.Tracker.Config{
      kind: "tapd",
      endpoint: "https://api.tapd.cn",
      auth: %{},
      provider: %{"platform" => %{}},
      lifecycle: %{}
    }
end
