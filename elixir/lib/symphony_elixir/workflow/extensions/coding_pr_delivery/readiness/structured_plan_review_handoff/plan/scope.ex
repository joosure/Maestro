defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Scope do
  @moduledoc """
  Canonical structured-plan scope checks for review handoff.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Check
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.ObservedEvidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: StructuredPlanContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Projection, as: StructuredPlanProjection

  @allowed_plan_statuses [StructuredPlanContract.active_plan_status(), StructuredPlanContract.handoff_ready_plan_status()]
  @superseded_plan_status StructuredPlanContract.superseded_plan_status()
  @closed_plan_status StructuredPlanContract.closed_plan_status()

  @plan_check_key "structured_execution_plan"
  @plan_superseded_reason "structured_plan_superseded"
  @plan_closed_reason "structured_plan_closed"
  @plan_not_ready_reason "structured_plan_not_ready"
  @plan_cross_run_reason "structured_plan_cross_run"
  @plan_scope_mismatch_reason "structured_plan_scope_mismatch"
  @plan_head_mismatch_reason "structured_plan_head_mismatch"

  @plan_superseded_detail "Superseded structured execution plans cannot satisfy review handoff."
  @plan_closed_detail "Closed structured execution plans cannot satisfy review handoff."
  @plan_not_ready_detail "Structured execution plan must be active or handoff_ready."
  @plan_cross_run_detail "Structured execution plan belongs to a different run."
  @plan_scope_issue_detail "Structured execution plan belongs to a different issue."
  @plan_scope_profile_detail "Structured execution plan belongs to a different workflow profile."
  @plan_scope_route_detail "Structured execution plan belongs to a different route."
  @plan_head_mismatch_detail "Structured execution plan head does not match the latest readiness head."

  @kind_key "kind"
  @version_key "version"

  @spec check(map(), map(), map()) :: {:ok, map()} | {:error, map()}
  def check(plan, context, observations) do
    cond do
      StructuredPlanProjection.status(plan) == @superseded_plan_status ->
        {:error, Check.failed(@plan_check_key, @plan_superseded_reason, @plan_superseded_detail, ObservedEvidence.plan(plan))}

      StructuredPlanProjection.status(plan) == @closed_plan_status ->
        {:error, Check.failed(@plan_check_key, @plan_closed_reason, @plan_closed_detail, ObservedEvidence.plan(plan))}

      StructuredPlanProjection.status(plan) not in @allowed_plan_statuses ->
        {:error, Check.failed(@plan_check_key, @plan_not_ready_reason, @plan_not_ready_detail, ObservedEvidence.plan(plan))}

      StructuredPlanProjection.run_id(plan) != Map.get(context, :run_id) ->
        {:error, Check.failed(@plan_check_key, @plan_cross_run_reason, @plan_cross_run_detail, ObservedEvidence.plan(plan))}

      not issue_matches?(plan, Map.get(context, :issue_ids, [])) ->
        {:error, Check.failed(@plan_check_key, @plan_scope_mismatch_reason, @plan_scope_issue_detail, ObservedEvidence.plan(plan))}

      not profile_matches?(plan, Map.get(context, :workflow_profile)) ->
        {:error, Check.failed(@plan_check_key, @plan_scope_mismatch_reason, @plan_scope_profile_detail, ObservedEvidence.plan(plan))}

      route_key_mismatch?(plan, Map.get(context, :route_key)) ->
        {:error, Check.failed(@plan_check_key, @plan_scope_mismatch_reason, @plan_scope_route_detail, ObservedEvidence.plan(plan))}

      Evidence.head_mismatch?(Evidence.latest_repo_head(plan), Evidence.current_head(observations)) ->
        {:error, Check.stale(@plan_check_key, @plan_head_mismatch_reason, @plan_head_mismatch_detail, ObservedEvidence.plan(plan))}

      true ->
        {:ok, Check.passed(@plan_check_key, ObservedEvidence.plan(plan))}
    end
  end

  defp issue_matches?(plan, issue_ids) when is_list(issue_ids) do
    issue_ids = Enum.uniq(issue_ids)

    issue_ids == [] or
      StructuredPlanProjection.issue_id(plan) in issue_ids or
      StructuredPlanProjection.issue_identifier(plan) in issue_ids
  end

  defp profile_matches?(plan, %{@kind_key => kind, @version_key => version}) do
    profile = StructuredPlanProjection.workflow_profile(plan) || %{}
    Map.get(profile, @kind_key) == kind and Map.get(profile, @version_key) == version
  end

  defp profile_matches?(_plan, _profile), do: true

  defp route_key_mismatch?(_plan, nil), do: false
  defp route_key_mismatch?(plan, route_key), do: StructuredPlanProjection.route_key(plan) != route_key
end
