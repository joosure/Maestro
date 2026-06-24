defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Probe do
  @moduledoc false

  alias SymphonyElixir.Smoke.ResultStatus
  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Report

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
        {failed(id, Diagnostics.exception(exception), elapsed_ms(monotonic_time_ms, started_at_ms)), {:error, exception}}
    catch
      kind, reason ->
        {failed(id, Diagnostics.caught(kind, reason), elapsed_ms(monotonic_time_ms, started_at_ms)), {:error, {kind, reason}}}
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
    %{id: id, ok: false, duration_ms: duration_ms, summary: ResultStatus.failed(), error: format_reason(reason)}
  end

  defp elapsed_ms(monotonic_time_ms, started_at_ms) do
    max(monotonic_time_ms.() - started_at_ms, 0)
  end

  defp format_reason(reason) when is_binary(reason), do: String.slice(reason, 0, 256)
  defp format_reason(reason) when is_atom(reason) and not is_nil(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_map(reason), do: reason |> bounded_reason_fields() |> Enum.join(" ")
  defp format_reason(reason), do: "value_type=#{Diagnostics.type_name(reason)}"

  defp bounded_reason_fields(reason) do
    reason
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> "#{key}=#{bounded_reason_value(value)}" end)
  end

  defp bounded_reason_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp bounded_reason_value(value) when is_binary(value), do: String.slice(value, 0, 128)
  defp bounded_reason_value(value) when is_boolean(value), do: to_string(value)
  defp bounded_reason_value(value) when is_integer(value), do: Integer.to_string(value)
  defp bounded_reason_value(nil), do: "nil"
  defp bounded_reason_value(value), do: "type:#{Diagnostics.type_name(value)}"
end
