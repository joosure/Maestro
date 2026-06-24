defmodule SymphonyElixir.Agent.ExecutionPlan.Store.Guards do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Store, as: StoreErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRequirement
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Item
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Plan
  alias SymphonyElixir.Agent.ExecutionPlan.Record.StatusReason
  alias SymphonyElixir.Agent.ExecutionPlan.Store.ErrorResults

  @complete_status Contract.complete_item_status()
  @skipped_status Contract.skipped_item_status()
  @reason_statuses [
    Contract.blocked_item_status(),
    Contract.skipped_item_status(),
    Contract.failed_item_status()
  ]

  @spec plan_id_available({:ok, Plan.t()} | {:error, map()}, Plan.t()) :: :ok | {:error, map()}
  def plan_id_available(fetch_result, %Plan{} = plan) do
    plan_not_found_code = StoreErrorCodes.plan_not_found()

    case fetch_result do
      {:ok, _plan} -> {:error, ErrorResults.plan_conflict(plan.plan_id)}
      {:error, %{code: ^plan_not_found_code}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec same_plan_id(String.t(), Plan.t()) :: :ok | {:error, map()}
  def same_plan_id(plan_id, %Plan{} = plan) do
    if plan.plan_id == plan_id, do: :ok, else: {:error, ErrorResults.plan_id_mismatch(plan_id, plan.plan_id)}
  end

  @spec revision_matches(Plan.t(), pos_integer()) :: :ok | {:error, map()}
  def revision_matches(%Plan{} = plan, expected_revision) do
    if plan.revision == expected_revision, do: :ok, else: {:error, ErrorResults.revision_conflict(plan.revision, expected_revision)}
  end

  @spec replacement_not_rollback(Plan.t(), Plan.t()) :: :ok | {:error, map()}
  def replacement_not_rollback(%Plan{} = current_plan, %Plan{} = replacement_plan) do
    if replacement_plan.revision >= current_plan.revision do
      :ok
    else
      {:error, ErrorResults.revision_rollback(current_plan.revision, replacement_plan.revision)}
    end
  end

  @spec plan_mutable(Plan.t()) :: :ok | {:error, map()}
  def plan_mutable(%Plan{} = plan) do
    if Contract.terminal_plan_status?(plan.status) do
      {:error,
       ErrorResults.item_update_not_allowed(nil, "Closed or superseded Agent execution plans do not accept item updates.", %{
         plan_id: plan.plan_id,
         status: plan.status
       })}
    else
      :ok
    end
  end

  @spec fetch_item(Plan.t(), String.t()) :: {:ok, Item.t()} | {:error, map()}
  def fetch_item(%Plan{} = plan, item_id) do
    case Enum.find(plan.items, &(&1.item_id == item_id)) do
      nil -> {:error, ErrorResults.item_not_found(item_id)}
      item -> {:ok, item}
    end
  end

  @spec status_update_allowed(Plan.t(), Item.t(), String.t(), keyword()) :: :ok | {:error, map()}
  def status_update_allowed(%Plan{} = plan, %Item{} = item, next_status, opts) do
    with :ok <- status_reason_present(item, next_status, opts),
         :ok <- dependencies_satisfied(plan, item, next_status),
         :ok <- evidence_satisfied(item, next_status) do
      :ok
    end
  end

  @spec evidence_scope_matches(Plan.t(), map()) :: :ok | {:error, map()}
  def evidence_scope_matches(%Plan{} = plan, evidence_ref) when is_map(evidence_ref) do
    evidence = EvidenceRef.from_map(evidence_ref)

    cond do
      is_binary(evidence.run_id) and evidence.run_id != plan.context.run_id ->
        {:error,
         ErrorResults.evidence_scope_mismatch(evidence.evidence_id, %{
           expected_run_id: plan.context.run_id,
           observed_run_id: evidence.run_id
         })}

      is_binary(evidence.task_id) and evidence.task_id != plan.context.task_id ->
        {:error,
         ErrorResults.evidence_scope_mismatch(evidence.evidence_id, %{
           expected_task_id: plan.context.task_id,
           observed_task_id: evidence.task_id
         })}

      true ->
        :ok
    end
  end

  @spec agent_item_upsert_allowed(Plan.t(), Plan.t(), [String.t()]) :: :ok | {:error, map()}
  def agent_item_upsert_allowed(%Plan{} = current_plan, %Plan{} = candidate_plan, item_ids) when is_list(item_ids) do
    current_by_id = Map.new(current_plan.items, &{&1.item_id, &1})
    candidate_by_id = Map.new(candidate_plan.items, &{&1.item_id, &1})

    item_ids
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn item_id, :ok ->
      candidate_item = Map.get(candidate_by_id, item_id)
      current_item = Map.get(current_by_id, item_id)

      case agent_item_upsert_item_allowed(item_id, current_item, candidate_item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp agent_item_upsert_item_allowed(item_id, _current_item, nil) do
    {:error, ErrorResults.invalid_agent_item(item_id)}
  end

  defp agent_item_upsert_item_allowed(item_id, %Item{} = current_item, %Item{} = candidate_item) do
    cond do
      not agent_owned_item?(current_item) ->
        {:error, ErrorResults.item_update_not_allowed(item_id, "Agent execution plan tools cannot replace backend-owned, policy-owned, or operator-owned items.")}

      true ->
        candidate_agent_item_upsert_allowed(candidate_item)
    end
  end

  defp agent_item_upsert_item_allowed(_item_id, nil, %Item{} = candidate_item) do
    candidate_agent_item_upsert_allowed(candidate_item)
  end

  defp candidate_agent_item_upsert_allowed(%Item{} = item) do
    cond do
      item.owned_by != Contract.agent_owner() ->
        {:error, ErrorResults.item_update_not_allowed(item.item_id, "Agent execution plan tools can only upsert agent-owned items.")}

      item.source != Contract.agent_draft_source() ->
        {:error, ErrorResults.item_update_not_allowed(item.item_id, "Agent execution plan tools can only upsert agent-draft items.")}

      item.required != false ->
        {:error, ErrorResults.item_update_not_allowed(item.item_id, "Agent execution plan tools cannot create required items.")}

      item.criticality != Contract.informational_criticality() ->
        {:error, ErrorResults.item_update_not_allowed(item.item_id, "Agent execution plan tools cannot create critical items.")}

      item.evidence_requirements != [] ->
        {:error, ErrorResults.item_update_not_allowed(item.item_id, "Agent execution plan tools cannot create evidence-bound items.")}

      item.evidence_refs != [] ->
        {:error, ErrorResults.item_update_not_allowed(item.item_id, "Agent execution plan tools cannot attach evidence through item upsert.")}

      true ->
        :ok
    end
  end

  defp agent_owned_item?(%Item{} = item) do
    item.owned_by == Contract.agent_owner() and
      item.source == Contract.agent_draft_source() and
      item.required == false and
      item.criticality == Contract.informational_criticality()
  end

  defp status_reason_present(%Item{} = item, next_status, opts) when next_status in @reason_statuses do
    cond do
      bounded_status_reason?(Keyword.get(opts, :status_reason)) ->
        :ok

      bounded_status_reason?(item.status_reason) ->
        :ok

      true ->
        {:error, ErrorResults.item_update_not_allowed(item.item_id, "Blocked, skipped, and failed item statuses require a bounded status_reason.")}
    end
  end

  defp status_reason_present(_item, _next_status, _opts), do: :ok

  defp bounded_status_reason?(%StatusReason{reason_code: reason_code}), do: non_empty_string?(reason_code)

  defp bounded_status_reason?(reason) when is_map(reason) do
    reason
    |> Map.get(Fields.reason_code())
    |> non_empty_string?()
  end

  defp bounded_status_reason?(_reason), do: false

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp dependencies_satisfied(_plan, _item, next_status) when next_status != @complete_status, do: :ok

  defp dependencies_satisfied(%Plan{} = plan, %Item{} = item, _next_status) do
    item_by_id = Map.new(plan.items, &{&1.item_id, &1})

    unsatisfied =
      item.depends_on
      |> Enum.map(&Map.get(item_by_id, &1))
      |> Enum.reject(&dependency_satisfied?/1)

    if unsatisfied == [] do
      :ok
    else
      {:error, ErrorResults.item_update_not_allowed(item.item_id, "Item dependencies must be complete or accepted as skipped before completion.")}
    end
  end

  defp dependency_satisfied?(%Item{status: status}), do: status in [@complete_status, @skipped_status]
  defp dependency_satisfied?(_item), do: false

  defp evidence_satisfied(_item, next_status) when next_status != @complete_status, do: :ok

  defp evidence_satisfied(%Item{} = item, _next_status) do
    unsatisfied =
      item.evidence_requirements
      |> Enum.filter(&required_requirement?/1)
      |> Enum.reject(&requirement_satisfied?(&1, item.evidence_refs))

    if unsatisfied == [] do
      :ok
    else
      {:error, ErrorResults.evidence_requirements_unsatisfied(item.item_id, Enum.map(unsatisfied, & &1.evidence_kind))}
    end
  end

  defp required_requirement?(%EvidenceRequirement{required: false}), do: false
  defp required_requirement?(%EvidenceRequirement{}), do: true

  defp requirement_satisfied?(%EvidenceRequirement{} = requirement, evidence_refs) do
    Enum.any?(evidence_refs, fn ref ->
      ref.evidence_kind == requirement.evidence_kind and
        ref.source in requirement.trust_classes and
        required_payload_fields_present?(ref.payload, requirement.required_fields)
    end)
  end

  defp required_payload_fields_present?(payload, required_fields) when is_map(payload) and is_list(required_fields) do
    Enum.all?(required_fields, &Map.has_key?(payload, &1))
  end

  defp required_payload_fields_present?(_payload, _required_fields), do: false
end
