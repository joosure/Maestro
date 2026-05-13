defmodule SymphonyWorkerDaemon.RateLimiter.PruningTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.RateLimiter.Pruning

  test "keeps state when bucket count and prune interval are within limits" do
    state = %{
      buckets: %{{:api, "owner-a"} => %{window_started_at_ms: 900}},
      max_buckets: 10,
      last_pruned_at_ms: 950
    }

    assert Pruning.maybe_prune(state, 1_000, 500) == state
  end

  test "removes expired buckets and updates prune timestamp" do
    state = %{
      buckets: %{
        {:api, "active"} => %{window_started_at_ms: 900},
        {:api, "expired"} => %{window_started_at_ms: 300}
      },
      max_buckets: 1,
      last_pruned_at_ms: 400
    }

    assert %{
             buckets: %{{:api, "active"} => %{window_started_at_ms: 900}},
             last_pruned_at_ms: 1_000
           } = Pruning.maybe_prune(state, 1_000, 500)
  end
end
