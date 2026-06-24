defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage do
  @moduledoc """
  Storage behaviour for workflow execution-plan adoption envelopes.

  The workflow backend owns only workflow-specific envelope fields and active
  route indexing. Generic plan payloads remain in
  `SymphonyElixir.Agent.ExecutionPlan.Storage`.
  """

  @type state :: term()
  @type reason :: map() | term()

  @callback init(keyword()) :: {:ok, state()} | {:error, reason()}
  @callback fetch_envelope(state(), String.t()) :: {:ok, map()} | :error | {:error, reason()}
  @callback put_envelope(state(), map()) :: {:ok, state()} | {:error, reason()}
  @callback delete_envelope(state(), String.t()) :: {:ok, state()} | {:error, reason()}
  @callback active_plan_id(state(), term()) :: {:ok, String.t()} | :error | {:error, reason()}
  @callback list_plan_ids(state()) :: {:ok, [String.t()]} | {:error, reason()}
  @callback reset(state()) :: {:ok, state()} | {:error, reason()}
end
