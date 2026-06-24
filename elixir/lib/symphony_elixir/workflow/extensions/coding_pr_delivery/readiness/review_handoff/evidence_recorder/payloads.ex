defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads do
  @moduledoc """
  Facade for Coding PR Delivery review-handoff payload projection.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.IssueKeys
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Repo
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.RepoProvider
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Tracker
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Workpad
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ToolContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.EvidencePayload

  @workpad_key Evidence.workpad_key()
  @change_proposal_key Evidence.change_proposal_key()
  @evidence_kind_key Evidence.evidence_kind_key()
  @workpad_evidence_kind Evidence.workpad_evidence_kind()
  @tracker_change_proposal_evidence_kind Evidence.tracker_change_proposal_evidence_kind()

  @spec observations(String.t() | atom() | nil, term(), String.t(), term(), term(), keyword()) :: map()
  def observations(_source_kind, _source_context, tool, arguments, payload, opts) do
    case EvidencePayload.fetch(payload) do
      evidence when is_map(evidence) -> evidence_observation(evidence)
      _no_canonical_evidence -> inferred_observations(tool, arguments, payload, opts)
    end
  end

  @spec issue_keys(term(), keyword()) :: [String.t()]
  defdelegate issue_keys(arguments, opts), to: IssueKeys

  defp inferred_observations(tool, arguments, payload, opts) do
    case ToolContract.evidence_kind(tool) do
      :workpad -> Workpad.observation(payload)
      :tracker_change_proposal -> Tracker.observation(arguments, payload)
      :repo_commit -> Repo.commit_observation(payload)
      :repo_push -> Repo.push_observation(payload)
      :repo_diff_validation -> Repo.diff_validation_observation(arguments, payload)
      :repo_provider_change_proposal -> RepoProvider.change_proposal_observation(payload)
      :repo_change_proposal_checks -> payload |> Normalization.payload_value("checks") |> RepoProvider.checks_observation(opts)
      :repo_provider_feedback -> payload |> Normalization.payload_value("discussion") |> RepoProvider.feedback_observation()
      :repo_provider_snapshot -> RepoProvider.snapshot_observation(payload, opts)
      nil -> %{}
    end
  end

  defp evidence_observation(%{@evidence_kind_key => @workpad_evidence_kind, @workpad_key => workpad}) when is_map(workpad) do
    Workpad.canonical_observation(workpad)
  end

  defp evidence_observation(%{@evidence_kind_key => @tracker_change_proposal_evidence_kind, @change_proposal_key => change_proposal})
       when is_map(change_proposal) do
    Tracker.canonical_observation(change_proposal)
  end

  defp evidence_observation(_evidence), do: %{}
end
