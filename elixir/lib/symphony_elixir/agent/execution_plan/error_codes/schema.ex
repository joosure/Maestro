defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Schema do
  @moduledoc """
  Agent execution-plan schema-specific machine-code contract.

  Generic shape validation codes live in `ErrorCodes.Validation`. Evidence
  append and immutability codes live in `ErrorCodes.Evidence`.
  """

  @duplicate_item_id "duplicate_item_id"
  @missing_evidence_requirements "missing_evidence_requirements"
  @duplicate_evidence_id "duplicate_evidence_id"
  @invalid_dependency "invalid_dependency"
  @dependency_cycle "dependency_cycle"
  @invalid_identity_ref "invalid_identity_ref"

  @spec duplicate_item_id() :: String.t()
  def duplicate_item_id, do: @duplicate_item_id

  @spec missing_evidence_requirements() :: String.t()
  def missing_evidence_requirements, do: @missing_evidence_requirements

  @spec duplicate_evidence_id() :: String.t()
  def duplicate_evidence_id, do: @duplicate_evidence_id

  @spec invalid_dependency() :: String.t()
  def invalid_dependency, do: @invalid_dependency

  @spec dependency_cycle() :: String.t()
  def dependency_cycle, do: @dependency_cycle

  @spec invalid_identity_ref() :: String.t()
  def invalid_identity_ref, do: @invalid_identity_ref
end
