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
    OperatorApplyRecord,
    OperatorApplyPlan,
    Phase2ClaimTemplate,
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

  @spec phase2_claim_templates() :: [String.t()]
  defdelegate phase2_claim_templates, to: Phase2ClaimTemplate, as: :templates

  @spec phase2_claim_template(Phase2ClaimTemplate.template() | String.t(), keyword()) :: validation_result()
  defdelegate phase2_claim_template(template, opts \\ []), to: Phase2ClaimTemplate, as: :build

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

  @spec operator_apply_plan(map()) :: {:ok, map()}
  defdelegate operator_apply_plan(request), to: OperatorApplyPlan, as: :build

  @spec validate_operator_apply_record(map()) :: validation_result()
  defdelegate validate_operator_apply_record(record), to: OperatorApplyRecord, as: :validate
end
