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
    EnablementRequestTemplate,
    EvidencePacket,
    EvidencePacketTemplate,
    EvidenceRunbook,
    ObservationDecision,
    ObservationStatus,
    ObservationStatusTemplate,
    OperatorApplyRecord,
    OperatorApplyRecordTemplate,
    OperatorApplyPlan,
    Phase2ClaimTemplate,
    ProviderMatrix,
    ReviewDecision,
    ReviewPacket,
    ReviewPacketTemplate,
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

  @spec phase2_evidence_packet_template(map()) :: validation_result()
  defdelegate phase2_evidence_packet_template(claim), to: EvidencePacketTemplate, as: :build

  @spec validate_review_packet(map()) :: validation_result()
  defdelegate validate_review_packet(packet), to: ReviewPacket, as: :validate

  @spec phase4_review_packet_template(map()) :: validation_result()
  defdelegate phase4_review_packet_template(evidence_packet), to: ReviewPacketTemplate, as: :build

  @spec review_decision(map()) :: {:ok, map()}
  defdelegate review_decision(packet), to: ReviewDecision, as: :build

  @spec validate_enablement_request(map()) :: validation_result()
  defdelegate validate_enablement_request(request), to: EnablementRequest, as: :validate

  @spec enablement_request_template(map(), keyword()) :: validation_result()
  defdelegate enablement_request_template(review_decision, opts \\ []), to: EnablementRequestTemplate, as: :build

  @spec operator_apply_plan(map()) :: {:ok, map()}
  defdelegate operator_apply_plan(request), to: OperatorApplyPlan, as: :build

  @spec validate_operator_apply_record(map()) :: validation_result()
  defdelegate validate_operator_apply_record(record), to: OperatorApplyRecord, as: :validate

  @spec operator_apply_record_template(map()) :: validation_result()
  defdelegate operator_apply_record_template(plan), to: OperatorApplyRecordTemplate, as: :build

  @spec validate_observation_status(map()) :: validation_result()
  defdelegate validate_observation_status(status), to: ObservationStatus, as: :validate

  @spec observation_status_template(map()) :: validation_result()
  defdelegate observation_status_template(apply_record), to: ObservationStatusTemplate, as: :build

  @spec observation_decision(map()) :: {:ok, map()}
  defdelegate observation_decision(status), to: ObservationDecision, as: :build
end
