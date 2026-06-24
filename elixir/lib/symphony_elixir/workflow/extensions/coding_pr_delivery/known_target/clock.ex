defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Clock do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Error

  @spec now_ms(keyword()) :: {:ok, integer()} | {:error, map()}
  def now_ms(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.fetch(opts, :now_ms) do
        {:ok, now_ms} when is_integer(now_ms) -> {:ok, now_ms}
        {:ok, now_ms} -> {:error, Error.invalid_now_ms(now_ms)}
        :error -> {:ok, system_time_ms()}
      end
    else
      {:error, Error.invalid_options(opts)}
    end
  end

  def now_ms(opts), do: {:error, Error.invalid_options(opts)}

  @spec system_time_ms() :: integer()
  def system_time_ms, do: System.system_time(:millisecond)
end
