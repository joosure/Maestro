defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.EvidenceRefs do
  @moduledoc """
  Evidence-ref store policy for workflow structured plans.

  This module validates workflow evidence scope, appends immutable matching refs,
  and invokes canonical reconciliation. It consumes canonical plan/evidence maps;
  raw tool payload binding remains owned by `EvidenceBinding`.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Record
  alias SymphonyElixir.Storage.Scrubber

  @spec record_and_reconcile(map(), [map()], keyword()) :: {:ok, map()} | {:error, map()}
  def record_and_reconcile(plan, evidence_refs, opts) when is_map(plan) and is_list(evidence_refs) and is_list(opts) do
    with {:ok, scrubbed_refs} <- Scrubber.scrub_map_list(evidence_refs, opts),
         {:ok, valid_refs} <- validate_evidence_refs(scrubbed_refs),
         :ok <- ensure_scope(plan, valid_refs),
         {:ok, updated_plan} <- record_refs_and_reconcile(plan, valid_refs, opts) do
      {:ok, updated_plan}
    end
  end

  defp validate_evidence_refs(evidence_refs) do
    Enum.reduce_while(evidence_refs, {:ok, []}, fn evidence_ref, {:ok, refs} ->
      case Evidence.validate_ref(evidence_ref) do
        {:ok, ref} -> {:cont, {:ok, refs ++ [ref]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_scope(plan, evidence_refs) do
    Enum.reduce_while(evidence_refs, :ok, fn ref, :ok ->
      cond do
        Map.get(ref, AgentFields.run_id()) != Map.get(plan, Fields.run_id()) ->
          {:halt,
           {:error,
            %{
              code: ErrorCodes.cross_run_evidence_not_allowed(),
              message: "Structured execution plan evidence must belong to the plan run.",
              plan_run_id: Map.get(plan, Fields.run_id()),
              evidence_run_id: Map.get(ref, AgentFields.run_id())
            }}}

        Map.get(ref, Fields.issue_id()) not in [Map.get(plan, Fields.issue_id()), Map.get(plan, Fields.issue_identifier())] ->
          {:halt,
           {:error,
            %{
              code: ErrorCodes.cross_issue_evidence_not_allowed(),
              message: "Structured execution plan evidence must belong to the plan issue.",
              plan_issue_id: Map.get(plan, Fields.issue_id()),
              evidence_issue_id: Map.get(ref, Fields.issue_id())
            }}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp record_refs_and_reconcile(plan, evidence_refs, opts) do
    original_items = Map.fetch!(plan, Fields.items())

    with {:ok, items_with_refs} <- record_matching_refs(original_items, evidence_refs),
         {:ok, reconciled_plan} <- Reconciler.reconcile(Map.put(plan, Fields.items(), items_with_refs)) do
      reconciled_items = Map.fetch!(reconciled_plan, Fields.items())

      if original_items == reconciled_items do
        {:ok, plan}
      else
        {:ok, Record.put_items(plan, bump_changed_items(original_items, reconciled_items, opts), opts)}
      end
    end
  end

  defp record_matching_refs(items, evidence_refs) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, updated_items} ->
      case record_item_matching_refs(item, evidence_refs) do
        {:ok, updated_item} -> {:cont, {:ok, [updated_item | updated_items]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, updated_items} -> {:ok, Enum.reverse(updated_items)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_item_matching_refs(item, evidence_refs) when is_map(item) do
    if Map.get(item, AgentFields.status()) == AgentContract.superseded_item_status() do
      {:ok, item}
    else
      Enum.reduce_while(evidence_refs, {:ok, item}, fn evidence_ref, {:ok, current_item} ->
        if accepts_evidence_ref?(current_item, evidence_ref) do
          append_matching_ref(current_item, evidence_ref)
        else
          {:cont, {:ok, current_item}}
        end
      end)
    end
  end

  defp accepts_evidence_ref?(item, evidence_ref) do
    evidence_kind_key = AgentFields.evidence_kind()
    trust_classes_key = AgentFields.trust_classes()

    item
    |> Map.get(AgentFields.evidence_requirements(), [])
    |> Enum.any?(fn
      requirement when is_map(requirement) ->
        evidence_kind = Map.get(requirement, evidence_kind_key)
        trust_classes = Map.get(requirement, trust_classes_key, [])

        evidence_kind == Map.get(evidence_ref, AgentFields.evidence_kind()) and
          Map.get(evidence_ref, AgentFields.source()) in trust_classes

      _requirement ->
        false
    end)
  end

  defp append_matching_ref(item, evidence_ref) do
    case attached_evidence_ref(item, evidence_ref) do
      nil ->
        case Evidence.append_ref(item, evidence_ref) do
          {:ok, updated_item} -> {:cont, {:ok, updated_item}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      attached_ref ->
        if idempotent_evidence_replay?(attached_ref, evidence_ref) do
          {:cont, {:ok, item}}
        else
          {:halt,
           {:error,
            %{
              code: ErrorCodes.evidence_ref_conflict(),
              message: "Evidence references are immutable once attached.",
              evidence_id: Map.fetch!(evidence_ref, AgentFields.evidence_id())
            }}}
        end
    end
  end

  defp attached_evidence_ref(item, evidence_ref) do
    evidence_id = Map.fetch!(evidence_ref, AgentFields.evidence_id())

    item
    |> Map.get(AgentFields.evidence_refs(), [])
    |> Enum.find(&(Map.get(&1, AgentFields.evidence_id()) == evidence_id))
  end

  defp idempotent_evidence_replay?(attached_ref, evidence_ref) do
    Map.drop(attached_ref, [AgentFields.observed_at()]) == Map.drop(evidence_ref, [AgentFields.observed_at()])
  end

  defp bump_changed_items(original_items, reconciled_items, opts) do
    Enum.zip(original_items, reconciled_items)
    |> Enum.map(fn
      {item, item} -> item
      {_original_item, reconciled_item} -> Record.bump_item(reconciled_item, opts)
    end)
  end
end
