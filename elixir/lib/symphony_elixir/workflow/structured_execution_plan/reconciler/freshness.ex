defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.Freshness do
  @moduledoc """
  Determines whether evidence-bound items must be refreshed after repo changes.

  The freshness policy consumes canonical evidence refs only. Tool names and raw
  provider payload shapes stay outside this module.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Providers
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.Requirements

  @core_staleable_evidence_kinds [
    ToolMap.repo_diff_evidence_kind(),
    ToolMap.tracker_upsert_workpad_evidence_kind()
  ]
  @repo_change_evidence_kinds [
    ToolMap.repo_commit_evidence_kind(),
    ToolMap.repo_push_evidence_kind()
  ]

  @spec stale?(map(), [map()]) :: boolean()
  def stale?(item, all_items) when is_map(item) and is_list(all_items) do
    item_evidence_kinds = Requirements.requirement_kinds(item)

    Enum.any?(item_evidence_kinds, &staleable_evidence_kind?/1) and
      latest_repo_change_at(all_items) |> newer_than?(latest_item_requirement_evidence_at(item))
  end

  def stale?(_item, _all_items), do: false

  @spec staleable_evidence_kinds() :: [String.t()]
  def staleable_evidence_kinds, do: Enum.uniq(@core_staleable_evidence_kinds ++ Providers.staleable_evidence_kinds())

  @spec repo_change_evidence_kinds() :: [String.t()]
  def repo_change_evidence_kinds, do: @repo_change_evidence_kinds

  defp staleable_evidence_kind?(evidence_kind), do: evidence_kind in staleable_evidence_kinds()

  defp latest_repo_change_at(items) do
    items
    |> Enum.flat_map(&evidence_refs/1)
    |> Enum.filter(&(Map.get(&1, AgentFields.evidence_kind()) in @repo_change_evidence_kinds))
    |> latest_observed_at()
  end

  defp latest_item_requirement_evidence_at(item) do
    requirement_kinds = Requirements.requirement_kinds(item)

    item
    |> evidence_refs()
    |> Enum.filter(&(Map.get(&1, AgentFields.evidence_kind()) in requirement_kinds))
    |> latest_observed_at()
  end

  defp evidence_refs(item) when is_map(item) do
    case Map.get(item, AgentFields.evidence_refs()) do
      refs when is_list(refs) -> refs
      _other -> []
    end
  end

  defp evidence_refs(_item), do: []

  defp latest_observed_at(refs) do
    refs
    |> Enum.flat_map(fn ref ->
      case DateTime.from_iso8601(Map.get(ref, AgentFields.observed_at(), "")) do
        {:ok, datetime, _offset} -> [datetime]
        _other -> []
      end
    end)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp newer_than?(nil, _right), do: false
  defp newer_than?(_left, nil), do: true
  defp newer_than?(left, right), do: DateTime.compare(left, right) == :gt
end
