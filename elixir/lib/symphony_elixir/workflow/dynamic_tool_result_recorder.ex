defmodule SymphonyElixir.Workflow.DynamicToolResultRecorder do
  @moduledoc """
  Workflow-owned Dynamic Tool result recorder.

  This module is application assembly between the provider-neutral Dynamic Tool
  platform and workflow mechanisms. It lets workflow readiness and registered
  workflow extensions observe typed-tool results without tracker, repo, or
  repo-provider sources depending on concrete workflow business modules.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.ResultRecorder

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Dispatcher
  alias SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder

  @impl true
  def record_result(source_kind, source_context, tool, arguments, result, opts) when is_list(opts) do
    source_kind
    |> Dispatcher.record_tool_result(source_context, tool, arguments, result, dispatcher_opts(opts))
    |> maybe_emit_extension_recorder_failure(source_kind, tool, result, opts)

    _record_readiness = EvidenceRecorder.record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts)

    :ok
  end

  defp dispatcher_opts(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> Keyword.take([:tool_result_recorder_registry_opts, :tool_result_recorder_opts])
      |> Keyword.put_new(:tool_result_recorder_opts, Keyword.drop(opts, [:tool_result_recorder_registry_opts, :tool_result_recorder_opts]))
    else
      opts
    end
  end

  defp maybe_emit_extension_recorder_failure(:ok, _source_kind, _tool, _result, _opts), do: :ok

  defp maybe_emit_extension_recorder_failure({:error, reason}, source_kind, tool, result, opts) do
    emit_event(opts, :warning, :workflow_tool_result_recorder_failed, %{
      component: "workflow_dynamic_tool_result_recorder",
      code: Map.get(reason, :code),
      reason: reason_name(Map.get(reason, :reason)),
      recorder_id: Map.get(reason, :recorder_id),
      recorder_module: Map.get(reason, :recorder_module),
      source_kind: source_kind_diagnostic(source_kind),
      dynamic_tool_name: tool_diagnostic(tool),
      result_type: result_type(result)
    })

    :ok
  end

  defp emit_event(opts, level, event, fields) do
    opts
    |> emit_event_fn()
    |> then(& &1.(level, event, fields))
  end

  defp emit_event_fn(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Keyword.get(opts, :emit_event_fn, &ObservabilityLogger.emit/3)
    else
      &ObservabilityLogger.emit/3
    end
  end

  defp emit_event_fn(_opts), do: &ObservabilityLogger.emit/3

  defp reason_name(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_name(%{reason: reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_name(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp reason_name(_reason), do: nil

  defp source_kind_diagnostic(source_kind) when is_atom(source_kind) and not is_nil(source_kind), do: Atom.to_string(source_kind)
  defp source_kind_diagnostic(source_kind) when is_binary(source_kind), do: String.slice(source_kind, 0, 128)
  defp source_kind_diagnostic(_source_kind), do: nil

  defp tool_diagnostic(tool) when is_binary(tool), do: String.slice(tool, 0, 128)
  defp tool_diagnostic(_tool), do: nil

  defp result_type({:success, _payload}), do: "success"
  defp result_type({:failure, _payload}), do: "failure"
  defp result_type({:error, _reason}), do: "error"
  defp result_type(result), do: Diagnostics.type_name(result)
end
