defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder do
  @moduledoc """
  Mirrors successful typed workflow tool results into active structured plans.

  Recording is disabled by default and only runs when the caller explicitly
  enables structured execution plan recording through opts. This recorder is
  best-effort: it returns `:ok` to the tool path, but emits compact diagnostics
  when binding, plan resolution, or persistence fails.
  """

  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder.PlanResolver
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @component "structured_execution_plan_evidence_recorder"
  @binding_failed_event :structured_plan_evidence_binding_failed
  @plan_resolution_failed_event :structured_plan_evidence_plan_resolution_failed
  @record_failed_event :structured_plan_evidence_record_failed

  @spec record_typed_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) :: :ok
  def record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts \\ []) do
    if Options.enabled?(opts) do
      do_record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts)
    else
      :ok
    end
  end

  defp do_record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts) do
    case EvidenceBinding.bind_typed_tool_result(source_kind, source_context, tool, arguments, result, opts) do
      {:ok, []} ->
        :ok

      {:ok, evidence_refs} ->
        record_evidence_refs(evidence_refs, tool, opts)

      {:error, reason} ->
        emit_diagnostic(@binding_failed_event, reason, tool, opts, %{evidence_ref_count: 0})
        :ok
    end
  end

  defp record_evidence_refs(evidence_refs, tool, opts) do
    with {:ok, plan_id} <- PlanResolver.resolve_plan_id(opts),
         {:ok, _plan} <- Store.record_evidence_refs(plan_id, evidence_refs, Options.store_opts(opts)) do
      :ok
    else
      {:error, reason} ->
        event = if plan_resolution_error?(reason), do: @plan_resolution_failed_event, else: @record_failed_event
        emit_diagnostic(event, reason, tool, opts, %{evidence_ref_count: length(evidence_refs)})
        :ok
    end
  end

  defp plan_resolution_error?(%{code: code}) do
    code == Map.fetch!(Store.plan_not_found_error(nil), :code)
  end

  defp plan_resolution_error?(_reason), do: false

  defp emit_diagnostic(event, reason, tool, opts, fields) do
    ObsLogger.emit(
      :warning,
      event,
      fields
      |> Map.merge(Options.diagnostic_fields(opts))
      |> Map.merge(%{
        component: @component,
        tool_name: tool,
        error_code: error_code(reason),
        error: error_message(reason)
      })
    )
  end

  defp error_code(%{code: code}), do: code
  defp error_code(_reason), do: nil

  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(reason), do: inspect(reason)
end
