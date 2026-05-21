defmodule SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder.Behaviour do
  @moduledoc """
  Behaviour for policy-specific readiness evidence recorders.
  """

  @callback record_typed_tool_result(
              String.t() | atom() | nil,
              term(),
              String.t() | nil,
              term(),
              term(),
              keyword()
            ) :: :ok
end
