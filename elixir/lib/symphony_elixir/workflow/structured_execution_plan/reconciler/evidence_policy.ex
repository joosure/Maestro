defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.EvidencePolicy do
  @moduledoc """
  Evidence-kind-specific payload policy for workflow plan reconciliation.

  EvidenceBinding owns raw typed-tool result normalization. This module
  consumes the normalized payload contract and decides whether a canonical
  evidence ref can satisfy a matching requirement.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Providers
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceContract, as: Evidence

  @repo_push ToolMap.repo_push_evidence_kind()
  @repo_diff ToolMap.repo_diff_evidence_kind()

  @diff_check_key "check"

  @spec valid?(String.t(), map()) :: boolean()
  def valid?(@repo_push, payload), do: repo_push_valid?(payload)
  def valid?(@repo_diff, payload), do: Map.get(payload, @diff_check_key) == true
  def valid?(evidence_kind, payload), do: Providers.valid?(evidence_kind, payload)

  @spec diff_check_key() :: String.t()
  def diff_check_key, do: @diff_check_key

  defp repo_push_valid?(payload) when is_map(payload) do
    head_sha = Map.get(payload, Evidence.head_sha_key())
    published_head_sha = Map.get(payload, Evidence.published_head_sha_key())

    is_binary(head_sha) and is_binary(published_head_sha) and head_sha == published_head_sha
  end

  defp repo_push_valid?(_payload), do: false
end
