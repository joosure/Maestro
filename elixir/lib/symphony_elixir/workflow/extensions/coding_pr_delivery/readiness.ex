defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness do
  @moduledoc """
  Coding PR Delivery readiness contribution facade.

  The top-level extension module depends on this facade instead of individual
  review-handoff policy, recorder, and retry modules. That keeps the exported
  plugin manifest surface stable while this readiness subdomain evolves
  internally.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.TypedToolFailurePolicy

  @spec policies() :: [module()]
  def policies, do: [ReviewHandoff]

  @spec evidence_recorders() :: [module()]
  def evidence_recorders, do: [EvidenceRecorder]

  @spec evidence_providers() :: [module()]
  def evidence_providers, do: [EvidenceProvider]

  @spec retry_policies() :: map()
  def retry_policies, do: TypedToolFailurePolicy.retry_policies()

  @spec resource_identity(map(), term()) :: {String.t(), term()} | nil
  def resource_identity(runtime_metadata, arguments),
    do: TypedToolFailurePolicy.resource_identity(runtime_metadata, arguments)
end
