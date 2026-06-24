defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder do
  @moduledoc """
  Evidence-recorder facade for Coding PR Delivery review handoff.

  This is the module registered with the platform recorder registry. Tool-result
  payload projection lives in `EvidenceRecorder.Payloads` so the
  registered contribution boundary stays small and stable.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.EventEmitterDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceStore
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope
  alias SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder.Behaviour, as: EvidenceRecorderBehaviour

  @behaviour EvidenceRecorderBehaviour

  @component "workflow.extensions.coding_pr_delivery.readiness.review_handoff.evidence_recorder"
  @invalid_options_event :coding_pr_delivery_review_handoff_evidence_recorder_invalid_options
  @invalid_options_error "coding_pr_delivery_review_handoff_evidence_recorder_invalid_options"
  @observations_key Envelope.observations_key()

  @spec record_typed_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) :: :ok
  @impl EvidenceRecorderBehaviour
  def record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts \\ [])

  def record_typed_tool_result(source_kind, source_context, tool, arguments, {:success, payload}, opts)
      when is_binary(tool) do
    case Options.normalize(opts) do
      {:ok, opts} ->
        observations = Payloads.observations(source_kind, source_context, tool, arguments, payload, opts)
        keys = Payloads.issue_keys(arguments, opts)

        if map_size(observations) > 0 do
          EvidenceStore.record(keys, %{@observations_key => observations}, opts)
        else
          :ok
        end

      {:error, reason} ->
        emit_invalid_options(source_kind, tool, reason, opts)
        :ok
    end
  end

  def record_typed_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: :ok

  defp emit_invalid_options(source_kind, tool, reason, opts) when is_map(reason) do
    emit_event_fn(opts).(:warning, @invalid_options_event, %{
      component: @component,
      error_code: @invalid_options_error,
      operation: "record_typed_tool_result",
      tool_name: bounded_string(tool),
      dynamic_tool_source_kind: bounded_string(source_kind),
      result_summary: "ignored",
      payload_summary: %{reason: Map.get(reason, :reason), value_type: Map.get(reason, :value_type)}
    })

    :ok
  rescue
    _error -> :ok
  end

  defp emit_event_fn(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, :emit_event_fn) do
        emit_event_fn when is_function(emit_event_fn, 3) -> emit_event_fn
        _other -> &EventEmitterDefaults.emit/3
      end
    else
      &EventEmitterDefaults.emit/3
    end
  end

  defp emit_event_fn(_opts), do: &EventEmitterDefaults.emit/3

  defp bounded_string(value) when is_binary(value), do: value
  defp bounded_string(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp bounded_string(_value), do: nil
end
