defmodule SymphonyElixir.ChangeProposalReconciliation.TrackerCallOptions do
  @moduledoc false

  @fetch_keys [:env, :request_fun, :retry_delays_ms, :sleep_fun]
  @write_keys [:request_fun, :retry_delays_ms, :sleep_fun]

  @spec fetch(keyword()) :: keyword()
  def fetch(opts) when is_list(opts), do: Keyword.take(opts, @fetch_keys)

  @spec write(keyword()) :: keyword()
  def write(opts) when is_list(opts), do: Keyword.take(opts, @write_keys)
end
