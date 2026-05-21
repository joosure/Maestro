defmodule SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder do
  @moduledoc """
  Dispatches successful typed-tool results to registered readiness evidence recorders.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry

  @spec record_typed_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) :: :ok
  def record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts \\ []) do
    Enum.each(PolicyRegistry.evidence_recorders(), fn recorder ->
      recorder.record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts)
    end)

    :ok
  end
end
