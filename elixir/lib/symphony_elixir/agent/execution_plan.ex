defmodule SymphonyElixir.Agent.ExecutionPlan do
  @moduledoc """
  Provider-neutral Agent execution plan core.

  This namespace owns the generic plan contract, schema, status machine, and
  immutable evidence-ref helpers. Workflow-specific adoption layers may wrap
  these primitives, but they must not redefine the core status, revision, or
  evidence semantics.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.Schema
  alias SymphonyElixir.Agent.ExecutionPlan.Store

  @spec schema_id() :: String.t()
  def schema_id, do: Contract.schema_id()

  @spec validate(map()) :: {:ok, map()} | {:error, map()}
  def validate(plan), do: Schema.validate(plan)

  @spec create_plan(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def create_plan(plan, opts \\ []), do: Store.create(plan, opts)

  @spec fetch_plan(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def fetch_plan(plan_id, opts \\ []), do: Store.fetch(plan_id, opts)
end
