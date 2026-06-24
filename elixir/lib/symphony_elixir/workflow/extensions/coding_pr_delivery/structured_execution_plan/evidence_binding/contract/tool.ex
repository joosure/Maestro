defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Tool do
  @moduledoc """
  Tool and capability mapping for Coding PR Delivery structured-plan evidence.
  """

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.RepoProvider.Capabilities, as: RepoProviderCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.EvidenceKind

  @capability_key Metadata.Contract.capability()

  @repo_tool_evidence_kinds %{
    EvidenceKind.repo_create_or_update_change_proposal_evidence_kind() => EvidenceKind.repo_create_or_update_change_proposal_evidence_kind(),
    EvidenceKind.repo_change_proposal_snapshot_evidence_kind() => EvidenceKind.repo_change_proposal_snapshot_evidence_kind(),
    EvidenceKind.repo_read_change_proposal_checks_evidence_kind() => EvidenceKind.repo_read_change_proposal_checks_evidence_kind(),
    EvidenceKind.repo_read_change_proposal_discussion_evidence_kind() => EvidenceKind.repo_read_change_proposal_discussion_evidence_kind()
  }

  @capability_evidence_kinds %{
    RepoProviderCapabilities.create_or_update_change_proposal() => EvidenceKind.repo_create_or_update_change_proposal_evidence_kind(),
    RepoProviderCapabilities.change_proposal_snapshot() => EvidenceKind.repo_change_proposal_snapshot_evidence_kind(),
    RepoProviderCapabilities.read_change_proposal_checks() => EvidenceKind.repo_read_change_proposal_checks_evidence_kind(),
    RepoProviderCapabilities.read_change_proposal_discussion() => EvidenceKind.repo_read_change_proposal_discussion_evidence_kind(),
    TrackerCapabilities.attach_external_reference() => EvidenceKind.tracker_attach_change_proposal_evidence_kind()
  }

  @staleable_evidence_kinds [
    EvidenceKind.repo_read_change_proposal_checks_evidence_kind(),
    EvidenceKind.repo_read_change_proposal_discussion_evidence_kind()
  ]

  @spec evidence_kind(String.t(), keyword()) :: String.t() | nil
  def evidence_kind(tool, opts) when is_binary(tool) and is_list(opts) do
    if Keyword.keyword?(opts) do
      tool
      |> capability(opts)
      |> capability_evidence_kind()
      |> Kernel.||(Map.get(@repo_tool_evidence_kinds, tool))
    else
      nil
    end
  end

  def evidence_kind(_tool, _opts), do: nil

  @spec staleable_evidence_kinds() :: [String.t()]
  def staleable_evidence_kinds, do: @staleable_evidence_kinds

  defp capability(tool, opts) do
    opts
    |> Keyword.get(:tool_context)
    |> tool_metadata(tool)
    |> workflow_capability()
  end

  defp capability_evidence_kind(capability) when is_binary(capability), do: Map.get(@capability_evidence_kinds, capability)
  defp capability_evidence_kind(_capability), do: nil

  defp tool_metadata(%{tool_metadata: metadata}, tool) when is_map(metadata), do: Map.get(metadata, tool)
  defp tool_metadata(%{"tool_metadata" => metadata}, tool) when is_map(metadata), do: Map.get(metadata, tool)
  defp tool_metadata(_tool_context, _tool), do: nil

  defp workflow_capability(metadata) when is_map(metadata), do: Map.get(metadata, @capability_key)
  defp workflow_capability(_metadata), do: nil
end
