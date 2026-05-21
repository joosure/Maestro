defmodule SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry do
  @moduledoc """
  Registry of readiness policy integrations that hook into shared infrastructure.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoff
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffEvidenceRecorder

  @policies [ReviewHandoff]
  @evidence_recorders [ReviewHandoffEvidenceRecorder]

  @spec policies() :: [module()]
  def policies, do: @policies

  @spec evidence_recorders() :: [module()]
  def evidence_recorders, do: @evidence_recorders
end
