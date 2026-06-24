defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding do
  @moduledoc """
  Coding PR Delivery structured-plan evidence binding provider.

  This module owns the provider facade for PR/change-proposal typed-tool
  evidence. Machine vocabulary, payload extraction, identity fields, and URL
  policy live in focused `EvidenceBinding.*` modules so the facade remains a
  stable implementation of
  `Workflow.StructuredExecutionPlan.EvidenceBinding.Provider`.
  """

  @behaviour SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Provider

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.EvidenceKind
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Payload, as: PayloadContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Tool, as: ToolContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Url, as: UrlContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Identity
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Payload
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.UrlPolicy
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  @repo_create_or_update_change_proposal EvidenceKind.repo_create_or_update_change_proposal_evidence_kind()
  @repo_change_proposal_snapshot EvidenceKind.repo_change_proposal_snapshot_evidence_kind()
  @repo_read_change_proposal_checks EvidenceKind.repo_read_change_proposal_checks_evidence_kind()
  @repo_read_change_proposal_discussion EvidenceKind.repo_read_change_proposal_discussion_evidence_kind()
  @tracker_attach_change_proposal EvidenceKind.tracker_attach_change_proposal_evidence_kind()

  @impl true
  def evidence_kind(tool, opts) when is_binary(tool) and is_list(opts) do
    if Keyword.keyword?(opts), do: ToolContract.evidence_kind(tool, opts), else: nil
  end

  def evidence_kind(_tool, _opts), do: nil

  @impl true
  def identity_fields(evidence_kind), do: Identity.fields(evidence_kind)

  @impl true
  def normalize(@repo_create_or_update_change_proposal, source_kind, source_context, _arguments, payload) do
    Payload.creation_payload(source_kind, source_context, payload)
  end

  def normalize(@repo_change_proposal_snapshot, source_kind, source_context, _arguments, payload) do
    Payload.snapshot_payload(source_kind, source_context, payload)
  end

  def normalize(@repo_read_change_proposal_checks, _source_kind, _source_context, _arguments, payload) do
    Payload.checks_payload(payload)
  end

  def normalize(@repo_read_change_proposal_discussion, _source_kind, _source_context, _arguments, payload) do
    Payload.discussion_payload(payload)
  end

  def normalize(@tracker_attach_change_proposal, source_kind, _source_context, arguments, payload) do
    if Payload.change_proposal_reference?(arguments) do
      Payload.tracker_attachment_payload(source_kind, arguments, payload)
    else
      :unknown
    end
  end

  def normalize(_evidence_kind, _source_kind, _source_context, _arguments, _payload), do: :unknown

  @impl true
  def valid?(@repo_create_or_update_change_proposal, payload),
    do: payload |> Map.get(PayloadContract.url_key()) |> UrlPolicy.provider_change_proposal_url?()

  def valid?(@repo_read_change_proposal_checks, payload),
    do: Map.get(payload, PayloadContract.status_key()) in passing_check_statuses()

  def valid?(@repo_read_change_proposal_discussion, payload),
    do: Map.get(payload, PayloadContract.status_key()) in passing_discussion_statuses()

  def valid?(@tracker_attach_change_proposal, payload), do: Map.get(payload, PayloadContract.linked_to_tracker_key()) == true
  def valid?(_evidence_kind, _payload), do: :unknown

  @impl true
  def staleable_evidence_kinds, do: ToolContract.staleable_evidence_kinds()

  @spec passing_check_statuses() :: [String.t()]
  def passing_check_statuses, do: [Values.passed_status(), Values.not_required_status()]

  @spec passing_discussion_statuses() :: [String.t()]
  def passing_discussion_statuses, do: [Values.clear_status(), Values.not_required_status()]

  @spec allowed_change_proposal_url_schemes() :: [String.t()]
  def allowed_change_proposal_url_schemes, do: UrlContract.allowed_change_proposal_url_schemes()

  @spec repo_create_or_update_change_proposal_evidence_kind() :: String.t()
  def repo_create_or_update_change_proposal_evidence_kind, do: EvidenceKind.repo_create_or_update_change_proposal_evidence_kind()

  @spec repo_change_proposal_snapshot_evidence_kind() :: String.t()
  def repo_change_proposal_snapshot_evidence_kind, do: EvidenceKind.repo_change_proposal_snapshot_evidence_kind()

  @spec repo_read_change_proposal_checks_evidence_kind() :: String.t()
  def repo_read_change_proposal_checks_evidence_kind, do: EvidenceKind.repo_read_change_proposal_checks_evidence_kind()

  @spec repo_read_change_proposal_discussion_evidence_kind() :: String.t()
  def repo_read_change_proposal_discussion_evidence_kind, do: EvidenceKind.repo_read_change_proposal_discussion_evidence_kind()

  @spec tracker_attach_change_proposal_evidence_kind() :: String.t()
  def tracker_attach_change_proposal_evidence_kind, do: EvidenceKind.tracker_attach_change_proposal_evidence_kind()
end
