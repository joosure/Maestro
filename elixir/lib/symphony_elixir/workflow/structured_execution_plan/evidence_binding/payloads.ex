defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Payloads do
  @moduledoc """
  Dispatches evidence payload normalization to domain-specific payload modules.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Payloads.Repo
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Payloads.Tracker
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Providers
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap

  @repo_commit ToolMap.repo_commit_evidence_kind()
  @repo_push ToolMap.repo_push_evidence_kind()
  @repo_diff ToolMap.repo_diff_evidence_kind()
  @tracker_upsert_workpad ToolMap.tracker_upsert_workpad_evidence_kind()
  @tracker_move_issue ToolMap.tracker_move_issue_evidence_kind()

  @spec normalize(String.t(), String.t() | atom() | nil, term(), term(), map()) :: {:ok, map()} | :unknown
  def normalize(@repo_commit, source_kind, source_context, arguments, payload),
    do: Repo.normalize(@repo_commit, source_kind, source_context, arguments, payload)

  def normalize(@repo_push, source_kind, source_context, arguments, payload),
    do: Repo.normalize(@repo_push, source_kind, source_context, arguments, payload)

  def normalize(@repo_diff, source_kind, source_context, arguments, payload),
    do: Repo.normalize(@repo_diff, source_kind, source_context, arguments, payload)

  def normalize(@tracker_upsert_workpad, source_kind, source_context, arguments, payload),
    do: Tracker.normalize(@tracker_upsert_workpad, source_kind, source_context, arguments, payload)

  def normalize(@tracker_move_issue, source_kind, source_context, arguments, payload),
    do: Tracker.normalize(@tracker_move_issue, source_kind, source_context, arguments, payload)

  def normalize(evidence_kind, source_kind, source_context, arguments, payload),
    do: Providers.normalize(evidence_kind, source_kind, source_context, arguments, payload)
end
