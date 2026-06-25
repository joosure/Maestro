defmodule SymphonyElixir.Workflow.StructuredExecutionPlan do
  @moduledoc """
  Thin facade for backend-owned structured execution plan primitives.

  This facade exposes internal schema, status-machine, evidence-ref, and store
  boundaries. Provider tools, Dynamic Tool exposure, Workpad rendering, and
  readiness-policy integrations live behind separate explicit modules and gates.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.OperatorInspection
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @spec schema_id() :: String.t()
  def schema_id, do: Contract.schema_id()

  @spec gate_defaults() :: %{String.t() => boolean()}
  def gate_defaults, do: Contract.gate_defaults()

  @spec validate(map()) :: {:ok, map()} | {:error, map()}
  def validate(plan), do: Schema.validate(plan)

  @spec create_plan(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def create_plan(plan, opts \\ []), do: Store.create(plan, opts)

  @spec fetch_plan(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def fetch_plan(plan_id, opts \\ []), do: Store.fetch(plan_id, opts)

  @spec active_plan(String.t(), map(), String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def active_plan(run_id, workflow_profile, route_key, opts \\ []),
    do: Store.active_plan(run_id, workflow_profile, route_key, opts)

  @spec update_plan_status(String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_plan_status(plan_id, status, expected_revision, opts \\ []),
    do: Store.update_plan_status(plan_id, status, expected_revision, opts)

  @spec update_item_status(String.t(), String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_item_status(plan_id, item_id, status, expected_revision, opts \\ []),
    do: Store.update_item_status(plan_id, item_id, status, expected_revision, opts)

  @spec append_evidence_ref(String.t(), String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def append_evidence_ref(plan_id, item_id, evidence_ref, expected_revision, opts \\ []),
    do: Store.append_evidence_ref(plan_id, item_id, evidence_ref, expected_revision, opts)

  @spec operator_inspection(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def operator_inspection(plan, opts \\ []), do: OperatorInspection.build(plan, opts)
end
