defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Result do
  @moduledoc false

  @type t :: %{
          inspected_count: non_neg_integer(),
          enqueued_count: non_neg_integer(),
          changed_count: non_neg_integer(),
          due_count: non_neg_integer(),
          error_count: non_neg_integer()
        }

  @spec empty() :: t()
  def empty do
    %{
      inspected_count: 0,
      enqueued_count: 0,
      changed_count: 0,
      due_count: 0,
      error_count: 0
    }
  end

  @spec empty_error() :: t()
  def empty_error do
    empty()
    |> Map.put(:error_count, 1)
  end

  @spec record_success(t(), boolean(), boolean(), boolean(), boolean(), boolean()) :: t()
  def record_success(result, enqueued?, changed?, due?, update_error?, enqueue_error?) do
    result
    |> Map.update!(:inspected_count, &(&1 + 1))
    |> Map.update!(:enqueued_count, &(&1 + if(enqueued?, do: 1, else: 0)))
    |> Map.update!(:changed_count, &(&1 + if(changed?, do: 1, else: 0)))
    |> Map.update!(:due_count, &(&1 + if(due?, do: 1, else: 0)))
    |> Map.update!(:error_count, &(&1 + error_count(update_error?, enqueue_error?)))
  end

  @spec record_error(t()) :: t()
  def record_error(result) do
    result
    |> Map.update!(:inspected_count, &(&1 + 1))
    |> Map.update!(:error_count, &(&1 + 1))
  end

  defp error_count(true, true), do: 2
  defp error_count(true, false), do: 1
  defp error_count(false, true), do: 1
  defp error_count(false, false), do: 0
end
