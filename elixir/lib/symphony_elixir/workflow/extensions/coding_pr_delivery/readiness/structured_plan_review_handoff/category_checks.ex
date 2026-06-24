defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.CategoryChecks do
  @moduledoc """
  Structured-plan evidence category checks for review handoff.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceKinds
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Check
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.ObservedEvidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: StructuredPlanContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Projection, as: StructuredPlanProjection

  @complete_item_status "complete"
  @category_missing_detail "A critical structured plan item is required for this readiness fact."
  @category_stale_detail "Structured plan evidence is older than the latest repository change."
  @category_incomplete_detail "Critical structured plan item evidence is incomplete."

  @criticalities [
    StructuredPlanContract.handoff_blocking_criticality(),
    StructuredPlanContract.profile_required_criticality()
  ]

  @categories [
    %{
      key: "structured_plan_implementation",
      missing: "structured_plan_implementation_missing",
      incomplete: "structured_plan_implementation_incomplete",
      stale: "structured_plan_implementation_stale",
      evidence_kinds: EvidenceKinds.repo_change_kinds(),
      stale_after_repo?: false,
      head_bound?: false
    },
    %{
      key: "structured_plan_validation",
      missing: "structured_plan_validation_missing",
      incomplete: "structured_plan_validation_incomplete",
      stale: "structured_plan_validation_stale",
      evidence_kinds: [EvidenceKinds.repo_diff()],
      stale_after_repo?: true,
      head_bound?: true
    },
    %{
      key: "structured_plan_change_proposal",
      missing: "structured_plan_change_proposal_missing",
      incomplete: "structured_plan_change_proposal_incomplete",
      stale: "structured_plan_change_proposal_stale",
      evidence_kinds: EvidenceKinds.change_proposal_kinds(),
      stale_after_repo?: false,
      head_bound?: false
    },
    %{
      key: "structured_plan_tracker_linkage",
      missing: "structured_plan_tracker_linkage_missing",
      incomplete: "structured_plan_tracker_linkage_incomplete",
      stale: "structured_plan_tracker_linkage_stale",
      evidence_kinds: EvidenceKinds.tracker_linkage_kinds(),
      stale_after_repo?: false,
      head_bound?: false
    },
    %{
      key: "structured_plan_change_proposal_checks",
      missing: "structured_plan_change_proposal_checks_missing",
      incomplete: "structured_plan_change_proposal_checks_incomplete",
      stale: "structured_plan_change_proposal_checks_stale",
      evidence_kinds: EvidenceKinds.checks_kinds(),
      stale_after_repo?: true,
      head_bound?: true
    },
    %{
      key: "structured_plan_feedback",
      missing: "structured_plan_feedback_missing",
      incomplete: "structured_plan_feedback_incomplete",
      stale: "structured_plan_feedback_stale",
      evidence_kinds: EvidenceKinds.feedback_kinds(),
      stale_after_repo?: true,
      head_bound?: false
    },
    %{
      key: "structured_plan_handoff_record",
      missing: "structured_plan_handoff_record_missing",
      incomplete: "structured_plan_handoff_record_incomplete",
      stale: "structured_plan_handoff_record_stale",
      evidence_kinds: EvidenceKinds.handoff_record_kinds(),
      stale_after_repo?: true,
      head_bound?: false
    }
  ]

  @spec checks(map()) :: [map()]
  def checks(plan), do: Enum.map(@categories, &check(plan, &1))

  defp check(plan, category) do
    items = critical_items(plan, Map.fetch!(category, :evidence_kinds))

    cond do
      items == [] ->
        Check.missing(Map.fetch!(category, :key), Map.fetch!(category, :missing), @category_missing_detail, [])

      Enum.all?(items, &item_ready?(&1, plan, category)) ->
        Check.passed(Map.fetch!(category, :key), ObservedEvidence.category(items, category))

      Enum.any?(items, &item_stale?(&1, plan, category)) ->
        Check.stale(Map.fetch!(category, :key), Map.fetch!(category, :stale), @category_stale_detail, ObservedEvidence.category(items, category))

      true ->
        Check.failed(Map.fetch!(category, :key), Map.fetch!(category, :incomplete), @category_incomplete_detail, ObservedEvidence.category(items, category))
    end
  end

  defp critical_items(plan, evidence_kinds) do
    plan
    |> StructuredPlanProjection.items()
    |> Enum.filter(fn item ->
      StructuredPlanProjection.item_required?(item) and
        StructuredPlanProjection.item_criticality(item) in @criticalities and
        item_evidence_kinds(item) |> Enum.any?(&(&1 in evidence_kinds))
    end)
  end

  defp item_ready?(item, plan, category) do
    StructuredPlanProjection.item_status(item) == @complete_item_status and
      StructuredPlanProjection.item_satisfied?(item) and
      not item_stale?(item, plan, category) and
      not item_head_mismatch?(item, plan, category)
  end

  defp item_stale?(item, plan, %{stale_after_repo?: true} = category) do
    refs = Evidence.category_refs(item, Map.fetch!(category, :evidence_kinds))
    refs != [] and Evidence.newer_than?(Evidence.latest_repo_change_at(plan), Evidence.latest_observed_at(refs))
  end

  defp item_stale?(_item, _plan, _category), do: false

  defp item_head_mismatch?(item, plan, %{head_bound?: true} = category) do
    latest_repo_head = Evidence.latest_repo_head(plan)

    item
    |> Evidence.category_refs(Map.fetch!(category, :evidence_kinds))
    |> Enum.any?(fn ref -> Evidence.head_mismatch?(Evidence.payload_head(ref), latest_repo_head) end)
  end

  defp item_head_mismatch?(_item, _plan, _category), do: false

  defp item_evidence_kinds(item) do
    item
    |> StructuredPlanProjection.item_evidence_requirements()
    |> Enum.flat_map(fn
      %{} = requirement ->
        case StructuredPlanProjection.evidence_kind(requirement) do
          evidence_kind when is_binary(evidence_kind) -> [evidence_kind]
          _evidence_kind -> []
        end

      _requirement ->
        []
    end)
  end
end
