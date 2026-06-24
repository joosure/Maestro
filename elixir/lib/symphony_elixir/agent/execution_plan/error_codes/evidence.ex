defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Evidence do
  @moduledoc """
  Evidence-specific machine-code contract for Agent execution plans.

  Generic schema validation codes are owned by `ErrorCodes.Validation`.
  """

  @invalid_evidence_ref "invalid_evidence_ref"
  @invalid_evidence_refs "invalid_evidence_refs"
  @evidence_ref_conflict "evidence_ref_conflict"
  @evidence_scope_mismatch "evidence_scope_mismatch"
  @evidence_requirements_unsatisfied "evidence_requirements_unsatisfied"

  @spec invalid_evidence_ref() :: String.t()
  def invalid_evidence_ref, do: @invalid_evidence_ref

  @spec invalid_evidence_refs() :: String.t()
  def invalid_evidence_refs, do: @invalid_evidence_refs

  @spec evidence_ref_conflict() :: String.t()
  def evidence_ref_conflict, do: @evidence_ref_conflict

  @spec evidence_scope_mismatch() :: String.t()
  def evidence_scope_mismatch, do: @evidence_scope_mismatch

  @spec evidence_requirements_unsatisfied() :: String.t()
  def evidence_requirements_unsatisfied, do: @evidence_requirements_unsatisfied
end
