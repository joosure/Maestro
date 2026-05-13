defmodule SymphonyWorkerDaemon.RateLimiter.Bucket do
  @moduledoc false

  @spec current(map() | nil, integer(), pos_integer()) :: map()
  def current(nil, now_ms, _window_ms), do: %{window_started_at_ms: now_ms, count: 0}

  def current(%{window_started_at_ms: window_started_at_ms} = bucket, now_ms, window_ms) do
    if now_ms - window_started_at_ms >= window_ms do
      %{window_started_at_ms: now_ms, count: 0}
    else
      bucket
    end
  end

  @spec normalized_key(term()) :: String.t()
  def normalized_key(key) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(key))
    |> Base.encode16(case: :lower)
  end
end
