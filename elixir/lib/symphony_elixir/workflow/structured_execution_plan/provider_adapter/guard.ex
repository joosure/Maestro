defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Guard do
  @moduledoc """
  Fail-closed guard for provider-native task completion proposals.

  Provider-native complete/todo surfaces are non-authoritative. This guard
  ensures they cannot satisfy evidence-bound structured plan items.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Contract, as: AgentToolContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Result
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler

  @missing_limit 20

  @spec task_completed(map()) :: {:ok, map()} | {:error, map()}
  def task_completed(plan) when is_map(plan) do
    missing_items = missing_evidence_items(plan)

    if missing_items == [] do
      {:ok, Result.guard_passed()}
    else
      {:error, Result.guard_blocked(missing_items)}
    end
  end

  @spec missing_evidence_items(map()) :: [map()]
  def missing_evidence_items(plan) when is_map(plan) do
    plan
    |> Map.get(AgentFields.items(), [])
    |> Enum.filter(&critical_evidence_bound_item?/1)
    |> Enum.reject(&Reconciler.satisfied?/1)
    |> Enum.take(@missing_limit)
    |> Enum.map(&missing_evidence_item_summary/1)
  end

  defp missing_evidence_item_summary(item) do
    %{
      AgentFields.item_id() => Map.get(item, AgentFields.item_id()),
      AgentFields.status() => Map.get(item, AgentFields.status()),
      AgentToolContract.evidence_kinds_key() =>
        item
        |> Map.get(AgentFields.evidence_requirements(), [])
        |> Enum.map(&Map.get(&1, AgentFields.evidence_kind()))
        |> Enum.reject(&is_nil/1)
    }
  end

  defp critical_evidence_bound_item?(item) when is_map(item) do
    Map.get(item, AgentFields.required()) == true and
      Contract.evidence_required_criticality?(Map.get(item, AgentFields.criticality())) and
      Map.get(item, AgentFields.evidence_requirements(), []) != []
  end

  defp critical_evidence_bound_item?(_item), do: false
end
