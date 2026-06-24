defmodule SymphonyElixir.Agent.ExecutionPlan.Store.Commands do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Evidence
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record
  alias SymphonyElixir.Agent.ExecutionPlan.Schema
  alias SymphonyElixir.Agent.ExecutionPlan.StatusMachine
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Command

  alias SymphonyElixir.Agent.ExecutionPlan.Store.Command.{
    AppendEvidenceRef,
    Create,
    Delete,
    Fetch,
    Replace,
    Reset,
    UpdateItemStatus,
    UpdatePlanStatus,
    UpsertAgentItems
  }

  alias SymphonyElixir.Agent.ExecutionPlan.Store.Guards
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Mutations
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Persistence
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Server.State

  @type reply :: term()

  @spec run(Command.t(), State.t()) :: {reply(), State.t()}
  def run(%Create{plan: plan, opts: opts}, %State{} = state) do
    result =
      with {:ok, input_plan} <- Schema.normalize(plan),
           prepared_plan <- Mutations.prepare_new_plan(input_plan, opts),
           {:ok, valid_plan} <- normalize(prepared_plan),
           :ok <- Guards.plan_id_available(Persistence.fetch(state, valid_plan.plan_id), valid_plan) do
        Persistence.put(state, valid_plan)
      end

    reply_with_fetch(result, state, Map.get(plan, Fields.plan_id()))
  end

  def run(%Fetch{plan_id: plan_id}, %State{} = state) do
    {external(Persistence.fetch(state, plan_id)), state}
  end

  def run(%Delete{plan_id: plan_id}, %State{} = state) do
    case Persistence.delete(state, plan_id) do
      {:ok, next_state} -> {:ok, next_state}
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  def run(
        %Replace{
          plan_id: plan_id,
          replacement: replacement,
          expected_revision: expected_revision,
          opts: opts
        },
        %State{} = state
      ) do
    result =
      with {:ok, current_plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.revision_matches(current_plan, expected_revision),
           {:ok, replacement_plan} <- Schema.normalize(replacement),
           :ok <- Guards.same_plan_id(plan_id, replacement_plan),
           :ok <- Guards.replacement_not_rollback(current_plan, replacement_plan),
           prepared_plan <- Mutations.prepare_replacement(current_plan, replacement_plan, opts),
           {:ok, valid_plan} <- normalize(prepared_plan) do
        Persistence.put(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run(
        %UpdatePlanStatus{
          plan_id: plan_id,
          next_status: next_status,
          expected_revision: expected_revision,
          opts: opts
        },
        %State{} = state
      ) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.revision_matches(plan, expected_revision),
           :ok <- StatusMachine.validate_plan_transition(plan.status, next_status),
           updated_plan <- Mutations.update_plan_status(plan, next_status, opts),
           {:ok, valid_plan} <- normalize(updated_plan) do
        Persistence.put(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run(
        %UpdateItemStatus{
          plan_id: plan_id,
          item_id: item_id,
          next_status: next_status,
          expected_revision: expected_revision,
          opts: opts
        },
        %State{} = state
      ) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           {:ok, item} <- Guards.fetch_item(plan, item_id),
           :ok <- StatusMachine.validate_item_transition(item.status, next_status),
           :ok <- Guards.status_update_allowed(plan, item, next_status, opts),
           updated_plan <- Mutations.update_item_status(plan, item_id, next_status, opts),
           {:ok, valid_plan} <- normalize(updated_plan) do
        Persistence.put(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run(
        %AppendEvidenceRef{
          plan_id: plan_id,
          item_id: item_id,
          evidence_ref: evidence_ref,
          expected_revision: expected_revision,
          opts: opts
        },
        %State{} = state
      ) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           {:ok, _item} <- Guards.fetch_item(plan, item_id),
           {:ok, valid_evidence_ref} <- Evidence.validate_ref(evidence_ref),
           :ok <- Guards.evidence_scope_matches(plan, valid_evidence_ref),
           {:ok, updated_plan} <- Mutations.append_evidence_ref(plan, item_id, valid_evidence_ref, opts),
           {:ok, valid_plan} <- normalize(updated_plan) do
        if valid_plan == plan, do: {:ok, state}, else: Persistence.put(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run(
        %UpsertAgentItems{
          plan_id: plan_id,
          items: items,
          expected_revision: expected_revision,
          opts: opts
        },
        %State{} = state
      ) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           {:ok, updated_plan, upserted_item_ids} <- Mutations.upsert_agent_items(plan, items, opts),
           :ok <- Guards.agent_item_upsert_allowed(plan, updated_plan, upserted_item_ids) do
        Persistence.put(state, updated_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run(%Reset{}, %State{} = state) do
    case Persistence.reset(state) do
      {:ok, next_state} -> {:ok, next_state}
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  defp normalize(plan), do: plan |> Record.to_map() |> Schema.normalize()

  defp external({:ok, plan}), do: {:ok, Record.to_map(plan)}
  defp external({:error, reason}), do: {:error, reason}

  defp reply_with_fetch({:ok, next_state}, _previous_state, plan_id), do: {external(Persistence.fetch(next_state, plan_id)), next_state}
  defp reply_with_fetch({:error, reason}, previous_state, _plan_id), do: {{:error, reason}, previous_state}
end
