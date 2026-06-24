defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Identity do
  @moduledoc """
  Identity field contract for Coding PR Delivery structured-plan evidence kinds.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.EvidenceKind
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Payload, as: PayloadContract

  @identity_fields_by_evidence_kind %{
    EvidenceKind.repo_create_or_update_change_proposal_evidence_kind() => [
      PayloadContract.provider_kind_key(),
      PayloadContract.repository_key(),
      PayloadContract.number_key(),
      PayloadContract.url_key(),
      PayloadContract.head_ref_key(),
      PayloadContract.head_sha_key(),
      PayloadContract.action_key()
    ],
    EvidenceKind.repo_change_proposal_snapshot_evidence_kind() => [
      PayloadContract.provider_kind_key(),
      PayloadContract.repository_key(),
      PayloadContract.number_key(),
      PayloadContract.url_key(),
      PayloadContract.head_ref_key(),
      PayloadContract.head_sha_key(),
      PayloadContract.exists_key()
    ],
    EvidenceKind.repo_read_change_proposal_checks_evidence_kind() => [
      PayloadContract.status_key(),
      PayloadContract.head_sha_key(),
      PayloadContract.run_count_key()
    ],
    EvidenceKind.repo_read_change_proposal_discussion_evidence_kind() => [
      PayloadContract.status_key(),
      PayloadContract.actionable_count_key()
    ],
    EvidenceKind.tracker_attach_change_proposal_evidence_kind() => [
      PayloadContract.tracker_kind_key(),
      PayloadContract.attachment_id_key(),
      PayloadContract.url_key()
    ]
  }

  @spec fields(String.t()) :: [String.t()] | :unknown
  def fields(evidence_kind), do: Map.get(@identity_fields_by_evidence_kind, evidence_kind, :unknown)
end
