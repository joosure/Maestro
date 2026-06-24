defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes do
  @moduledoc """
  Workflow structured-plan store machine-code contract.

  Generic store, validation, and evidence codes remain owned by Agent
  execution-plan contracts. This module is the workflow store facade plus the
  owner for workflow-store-only codes.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Evidence, as: EvidenceErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Store, as: AgentStoreErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.ErrorCodes, as: SchemaErrorCodes

  @cross_run_evidence_not_allowed "cross_run_evidence_not_allowed"
  @cross_issue_evidence_not_allowed "cross_issue_evidence_not_allowed"
  @provider_session_event_conflict "provider_session_event_conflict"

  @spec plan_conflict() :: String.t()
  defdelegate plan_conflict, to: AgentStoreErrorCodes

  @spec plan_not_found() :: String.t()
  defdelegate plan_not_found, to: AgentStoreErrorCodes

  @spec revision_conflict() :: String.t()
  defdelegate revision_conflict, to: AgentStoreErrorCodes

  @spec item_update_not_allowed() :: String.t()
  defdelegate item_update_not_allowed, to: AgentStoreErrorCodes

  @spec item_not_found() :: String.t()
  defdelegate item_not_found, to: AgentStoreErrorCodes

  @spec store_unavailable() :: String.t()
  defdelegate store_unavailable, to: AgentStoreErrorCodes

  @spec schema_invalid() :: String.t()
  defdelegate schema_invalid, to: ValidationErrorCodes

  @spec evidence_ref_conflict() :: String.t()
  defdelegate evidence_ref_conflict, to: EvidenceErrorCodes

  @spec invalid_route_ref() :: String.t()
  defdelegate invalid_route_ref, to: SchemaErrorCodes

  @spec cross_run_evidence_not_allowed() :: String.t()
  def cross_run_evidence_not_allowed, do: @cross_run_evidence_not_allowed

  @spec cross_issue_evidence_not_allowed() :: String.t()
  def cross_issue_evidence_not_allowed, do: @cross_issue_evidence_not_allowed

  @spec provider_session_event_conflict() :: String.t()
  def provider_session_event_conflict, do: @provider_session_event_conflict
end
