defmodule SymphonyElixir.ChangeProposalReconciliation.OneShot.Probe do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.OneShot.Report

  @type result :: Report.probe_result()

  @spec run(String.t(), (-> integer()), (-> {:ok, String.t(), term()} | {:error, term()})) ::
          {result(), {:ok, term()} | {:error, term()}}
  def run(id, monotonic_time_ms, fun) when is_binary(id) and is_function(monotonic_time_ms, 0) and is_function(fun, 0) do
    started_at_ms = monotonic_time_ms.()

    try do
      case fun.() do
        {:ok, summary, value} ->
          {%{id: id, ok: true, duration_ms: elapsed_ms(monotonic_time_ms, started_at_ms), summary: summary, error: nil}, {:ok, value}}

        {:error, reason} ->
          {failed(id, reason, elapsed_ms(monotonic_time_ms, started_at_ms)), {:error, reason}}
      end
    rescue
      exception ->
        {failed(id, Exception.message(exception), elapsed_ms(monotonic_time_ms, started_at_ms)), {:error, exception}}
    end
  end

  @spec failed(String.t(), term()) :: result()
  def failed(id, reason) when is_binary(id) do
    failed(id, reason, 0)
  end

  @spec ok_value({:ok, term()} | term()) :: term() | nil
  def ok_value({:ok, value}), do: value
  def ok_value(_result), do: nil

  defp failed(id, reason, duration_ms) do
    %{id: id, ok: false, duration_ms: duration_ms, summary: "failed", error: format_reason(reason)}
  end

  defp elapsed_ms(monotonic_time_ms, started_at_ms) do
    max(monotonic_time_ms.() - started_at_ms, 0)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
