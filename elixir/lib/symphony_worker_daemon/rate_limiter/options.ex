defmodule SymphonyWorkerDaemon.RateLimiter.Options do
  @moduledoc false

  @default_window_ms 60_000

  @spec limit(keyword()) :: pos_integer() | :infinity
  def limit(opts) when is_list(opts) do
    case Keyword.get(opts, :limit) do
      value when is_integer(value) and value > 0 -> value
      :infinity -> :infinity
      _value -> 1
    end
  end

  @spec window_ms(keyword()) :: pos_integer()
  def window_ms(opts) when is_list(opts) do
    positive_integer(Keyword.get(opts, :window_ms), @default_window_ms)
  end

  @spec positive_integer(term(), pos_integer()) :: pos_integer()
  def positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  def positive_integer(_value, default), do: default
end
