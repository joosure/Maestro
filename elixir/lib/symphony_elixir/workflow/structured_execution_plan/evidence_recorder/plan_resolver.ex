defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder.PlanResolver do
  @moduledoc """
  Resolves the structured execution plan that should receive evidence refs.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @spec resolve_plan_id(keyword()) :: {:ok, String.t()} | {:error, map()}
  def resolve_plan_id(opts) when is_list(opts) do
    case Options.plan_id(opts) do
      plan_id when is_binary(plan_id) -> {:ok, plan_id}
      _value -> resolve_active_plan_id(opts)
    end
  end

  defp resolve_active_plan_id(opts) do
    with {:ok, scope} <- Options.active_plan_scope(opts),
         {:ok, plan} <- Store.active_plan(scope.run_id, scope.workflow_profile, scope.route_key, Options.store_opts(opts)),
         plan_id when is_binary(plan_id) <- Map.get(plan, Fields.plan_id()) do
      {:ok, plan_id}
    else
      :error -> {:error, Store.plan_not_found_error(nil)}
      {:error, reason} when is_map(reason) -> {:error, reason}
      _value -> {:error, Store.plan_not_found_error(nil)}
    end
  end
end
