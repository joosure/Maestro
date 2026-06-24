defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Events do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics

  @type run_result :: %{
          status: :ok | :skipped | :error,
          candidate_count: non_neg_integer(),
          enqueued_count: non_neg_integer(),
          error: String.t() | nil
        }

  @spec completed((atom(), atom(), map() -> term()), map(), run_result(), integer()) :: run_result()
  def completed(emit_event_fn, settings, result, started_at_ms) do
    emit_event_fn.(
      :info,
      Contract.event(:startup_backlog_bootstrap_completed),
      %{
        component: Contract.component(),
        producer: Contract.producer(:startup_backlog_bootstrap),
        tracker_kind: tracker_kind(settings),
        status: Atom.to_string(result.status),
        candidate_count: result.candidate_count,
        enqueued_count: result.enqueued_count,
        duration_ms: elapsed_ms(started_at_ms)
      }
    )

    result
  end

  @spec skipped(term(), (atom(), atom(), map() -> term()), integer()) :: run_result()
  def skipped(reason, emit_event_fn, started_at_ms) do
    emit_event_fn.(
      :info,
      Contract.event(:startup_backlog_bootstrap_completed),
      %{
        component: Contract.component(),
        producer: Contract.producer(:startup_backlog_bootstrap),
        status: Contract.producer_status(:skipped),
        skip_reason: skip_reason(reason),
        candidate_count: 0,
        enqueued_count: 0,
        duration_ms: elapsed_ms(started_at_ms)
      }
    )

    %{status: :skipped, candidate_count: 0, enqueued_count: 0, error: nil}
  end

  @spec failed(term(), (atom(), atom(), map() -> term()), integer()) :: run_result()
  def failed(reason, emit_event_fn, started_at_ms) do
    error = Diagnostics.error_string(reason)

    emit_event_fn.(
      :warning,
      Contract.event(:startup_backlog_bootstrap_completed),
      %{
        component: Contract.component(),
        producer: Contract.producer(:startup_backlog_bootstrap),
        status: Contract.producer_status(:error),
        error: error,
        candidate_count: 0,
        enqueued_count: 0,
        duration_ms: elapsed_ms(started_at_ms)
      }
    )

    %{status: :error, candidate_count: 0, enqueued_count: 0, error: error}
  end

  defp tracker_kind(%{tracker: tracker}), do: Defaults.tracker_kind(tracker)
  defp tracker_kind(%{"tracker" => tracker}), do: Defaults.tracker_kind(tracker)
  defp tracker_kind(_settings), do: nil

  defp elapsed_ms(started_at_ms), do: System.monotonic_time(:millisecond) - started_at_ms

  defp skip_reason(reason) when is_atom(reason) and not is_nil(reason), do: Atom.to_string(reason)
  defp skip_reason({reason, _value}) when is_atom(reason) and not is_nil(reason), do: Atom.to_string(reason)
  defp skip_reason(reason), do: Diagnostics.error_string(reason)
end
