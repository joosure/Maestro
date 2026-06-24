defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.TrackerCallOptions do
  @moduledoc false

  @fetch_keys [:env, :request_fun, :retry_delays_ms, :sleep_fun]
  @write_keys [:request_fun, :retry_delays_ms, :sleep_fun]

  @spec fetch(keyword()) :: keyword()
  def fetch(opts), do: take!(opts, @fetch_keys)

  @spec write(keyword()) :: keyword()
  def write(opts), do: take!(opts, @write_keys)

  defp take!(opts, keys) when is_list(opts) and is_list(keys) do
    unless Keyword.keyword?(opts), do: raise(ArgumentError, "tracker call options must be a keyword list")
    Keyword.take(opts, keys)
  end

  defp take!(_opts, _keys), do: raise(ArgumentError, "tracker call options must be a keyword list")
end
