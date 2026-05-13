defmodule SymphonyWorkerDaemon.RateLimiter.Pruning do
  @moduledoc false

  @spec maybe_prune(map(), integer(), pos_integer()) :: map()
  def maybe_prune(%{buckets: buckets, max_buckets: max_buckets, last_pruned_at_ms: last_pruned_at_ms} = state, now_ms, window_ms)
      when map_size(buckets) <= max_buckets and now_ms - last_pruned_at_ms < window_ms do
    state
  end

  def maybe_prune(%{buckets: buckets} = state, now_ms, window_ms) do
    buckets =
      Map.reject(buckets, fn {_key, %{window_started_at_ms: window_started_at_ms}} ->
        now_ms - window_started_at_ms >= window_ms
      end)

    %{state | buckets: buckets, last_pruned_at_ms: now_ms}
  end
end
