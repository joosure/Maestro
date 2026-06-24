defmodule SymphonyElixir.Agent.ExecutionPlan.Storage do
  @moduledoc """
  Storage behaviour for canonical `agent.execution_plan.v1` records.

  Implementations persist already-normalized Agent execution plans. They must
  not parse workflow envelopes, tracker fields, or Dynamic Tool payloads.
  Business rules stay in `SymphonyElixir.Agent.ExecutionPlan.Store`.
  """

  @type state :: term()
  @type reason :: map() | term()

  @callback init(keyword()) :: {:ok, state()} | {:error, reason()}
  @callback fetch_plan(state(), String.t()) :: {:ok, map()} | :error | {:error, reason()}
  @callback put_plan(state(), map()) :: {:ok, state()} | {:error, reason()}
  @callback delete_plan(state(), String.t()) :: {:ok, state()} | {:error, reason()}
  @callback reset(state()) :: {:ok, state()} | {:error, reason()}
end
