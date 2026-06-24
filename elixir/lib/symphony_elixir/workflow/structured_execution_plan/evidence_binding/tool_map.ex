defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap do
  @moduledoc """
  Tool-to-evidence binding contract for workflow structured plans.

  Provider-neutral repo tool names remain stable external contracts. Tracker
  provider-facing tool names are resolved through Dynamic Tool
  `capability` metadata so concrete tracker names do not leak into the
  structured-plan core.

  Evidence kinds and identity field sets are the canonical binding contract
  consumed by evidence binding and plan reconciliation.
  """

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Repo.Capabilities, as: RepoCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities

  @repo_commit_tool "repo_commit"
  @repo_push_tool "repo_push"
  @repo_diff_tool "repo_diff"

  @repo_commit_evidence_kind "repo_commit"
  @repo_push_evidence_kind "repo_push"
  @repo_diff_evidence_kind "repo_diff"
  @tracker_upsert_workpad_evidence_kind "tracker_upsert_workpad"
  @tracker_move_issue_evidence_kind "tracker_move_issue"

  @repo_tool_evidence_kinds %{
    @repo_commit_tool => @repo_commit_evidence_kind,
    @repo_push_tool => @repo_push_evidence_kind,
    @repo_diff_tool => @repo_diff_evidence_kind
  }

  @capability_evidence_kinds %{
    RepoCapabilities.commit() => @repo_commit_evidence_kind,
    RepoCapabilities.push() => @repo_push_evidence_kind,
    RepoCapabilities.diff() => @repo_diff_evidence_kind,
    TrackerCapabilities.upsert_workpad() => @tracker_upsert_workpad_evidence_kind,
    TrackerCapabilities.move_issue() => @tracker_move_issue_evidence_kind
  }

  @identity_fields_by_evidence_kind %{
    @repo_commit_evidence_kind => ["head_sha"],
    @repo_push_evidence_kind => ["branch", "head_sha", "published_head_sha"],
    @repo_diff_evidence_kind => ["check", "head_sha", "args"],
    @tracker_upsert_workpad_evidence_kind => ["tracker_kind", "workpad_id"],
    @tracker_move_issue_evidence_kind => ["tracker_kind", "issue_id", "state_name", "state_id"]
  }

  @capability_key Metadata.Contract.capability()

  @spec evidence_kind(String.t() | nil) :: String.t() | nil
  @spec evidence_kind(String.t() | nil, keyword()) :: String.t() | nil
  def evidence_kind(tool, opts \\ [])

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

  @spec capability_evidence_kind(String.t() | nil) :: String.t() | nil
  def capability_evidence_kind(capability) when is_binary(capability), do: Map.get(@capability_evidence_kinds, capability)
  def capability_evidence_kind(_capability), do: nil

  @spec identity_fields(String.t()) :: [String.t()]
  def identity_fields(evidence_kind), do: Map.get(@identity_fields_by_evidence_kind, evidence_kind, [])

  defp capability(tool, opts) do
    opts
    |> Keyword.get(:tool_context)
    |> tool_metadata(tool)
    |> workflow_capability()
  end

  defp tool_metadata(%{tool_metadata: metadata}, tool) when is_map(metadata), do: Map.get(metadata, tool)
  defp tool_metadata(%{"tool_metadata" => metadata}, tool) when is_map(metadata), do: Map.get(metadata, tool)
  defp tool_metadata(_tool_context, _tool), do: nil

  defp workflow_capability(metadata) when is_map(metadata), do: Map.get(metadata, @capability_key)
  defp workflow_capability(_metadata), do: nil

  @spec repo_commit_evidence_kind() :: String.t()
  def repo_commit_evidence_kind, do: @repo_commit_evidence_kind

  @spec repo_push_evidence_kind() :: String.t()
  def repo_push_evidence_kind, do: @repo_push_evidence_kind

  @spec repo_diff_evidence_kind() :: String.t()
  def repo_diff_evidence_kind, do: @repo_diff_evidence_kind

  @spec tracker_upsert_workpad_evidence_kind() :: String.t()
  def tracker_upsert_workpad_evidence_kind, do: @tracker_upsert_workpad_evidence_kind

  @spec tracker_move_issue_evidence_kind() :: String.t()
  def tracker_move_issue_evidence_kind, do: @tracker_move_issue_evidence_kind
end
