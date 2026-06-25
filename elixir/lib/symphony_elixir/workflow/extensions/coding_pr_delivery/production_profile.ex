defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile do
  @moduledoc """
  Facade for Coding PR Delivery production-profile admission checks.

  The functions here are pure review-packet helpers. They validate production
  evidence metadata and build diagnostic runbooks; they do not call providers,
  mutate workflow state, or enable production gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    Claim,
    EnablementRequest,
    EvidencePacket,
    EvidenceRunbook,
    ProviderMatrix,
    ReviewDecision,
    ReviewPacket,
    TypedToolException
  }

  @type validation_result :: {:ok, map()} | {:error, map()}

  @spec side_effect_modes() :: [String.t()]
  defdelegate side_effect_modes, to: ProviderMatrix

  @spec validate_provider_matrix(map()) :: validation_result()
  defdelegate validate_provider_matrix(claim), to: ProviderMatrix, as: :validate_claim

  @spec validate_provider_matrix_entry(map()) :: validation_result()
  defdelegate validate_provider_matrix_entry(entry), to: ProviderMatrix, as: :validate_entry

  @spec validate_typed_tool_exception(map()) :: validation_result()
  defdelegate validate_typed_tool_exception(record), to: TypedToolException, as: :validate_record

  @spec validate_claim(map()) :: validation_result()
  defdelegate validate_claim(claim), to: Claim, as: :validate

  @spec build_evidence_runbook(map()) :: validation_result()
  defdelegate build_evidence_runbook(claim), to: EvidenceRunbook, as: :build

  @spec validate_evidence_packet(map()) :: validation_result()
  defdelegate validate_evidence_packet(packet), to: EvidencePacket, as: :validate

  @spec validate_review_packet(map()) :: validation_result()
  defdelegate validate_review_packet(packet), to: ReviewPacket, as: :validate

  @spec review_decision(map()) :: {:ok, map()}
  defdelegate review_decision(packet), to: ReviewDecision, as: :build

  @spec validate_enablement_request(map()) :: validation_result()
  defdelegate validate_enablement_request(request), to: EnablementRequest, as: :validate
end
