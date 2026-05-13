defmodule SymphonyWorkerDaemon.OrphanSweeper.Result do
  @moduledoc false

  @type t :: %{
          candidates: non_neg_integer(),
          terminated: non_neg_integer(),
          already_exited: non_neg_integer(),
          skipped: non_neg_integer(),
          failed: non_neg_integer()
        }

  @spec empty() :: t()
  def empty do
    %{candidates: 0, terminated: 0, already_exited: 0, skipped: 0, failed: 0}
  end

  @spec accumulate(atom(), t()) :: t()
  def accumulate(:terminated, result), do: result |> inc(:candidates) |> inc(:terminated)
  def accumulate(:already_exited, result), do: result |> inc(:candidates) |> inc(:already_exited)
  def accumulate(:skipped, result), do: result |> inc(:candidates) |> inc(:skipped)
  def accumulate(:failed, result), do: result |> inc(:candidates) |> inc(:failed)

  defp inc(result, key), do: Map.update!(result, key, &(&1 + 1))
end
