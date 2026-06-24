defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Provider do
  @moduledoc """
  Behaviour for extension-owned structured-plan evidence binding rules.

  The structured-plan platform owns the stable binding mechanism. Workflow
  extensions own business-specific tool mappings, payload normalization, evidence
  identity fields, validity policy, and freshness classification.
  """

  @type evidence_kind :: String.t()

  @callback evidence_kind(String.t(), keyword()) :: evidence_kind() | nil
  @callback identity_fields(evidence_kind()) :: [String.t()] | :unknown
  @callback normalize(evidence_kind(), String.t() | atom() | nil, term(), term(), map()) ::
              {:ok, map()} | :unknown
  @callback valid?(evidence_kind(), map()) :: boolean() | :unknown
  @callback staleable_evidence_kinds() :: [evidence_kind()]
end
