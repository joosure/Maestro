defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Commands do
  @moduledoc """
  Transaction orchestration for workflow structured-plan store commands.

  Commands consume already-normalized message tuples from `Store.Server`, apply
  workflow Store policies, project to the generic Agent store, and persist the
  workflow envelope through `Store.Persistence`.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Storage.Scrubber
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.AgentOwnedItemPolicy
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Errors
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.EvidenceRefs
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Guards
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Persistence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ProviderSessionEvents
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Record
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Server.State
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Renderer

  @type reply :: term()
  @type command :: term()

  @spec run(command(), State.t()) :: {reply(), State.t()}
  def run({:create, plan}, %State{} = state) do
    result =
      with {:ok, valid_plan} <- Schema.validate(plan),
           :ok <- ensure_plan_id_available(state, valid_plan),
           :ok <- ensure_active_slot_available(state, valid_plan),
           {:ok, _agent_plan} <- Persistence.create_projected_plan(state, valid_plan) do
        Persistence.put_plan(state, valid_plan)
      end

    reply_with_fetch(result, state, Map.fetch!(plan, Fields.plan_id()))
  end

  def run({:fetch, plan_id}, %State{} = state) do
    {Persistence.fetch(state, plan_id), state}
  end

  def run({:active_plan, key}, %State{} = state) do
    result =
      case Persistence.active_plan_id(state, key) do
        {:ok, plan_id} ->
          Persistence.fetch(state, plan_id)

        {:error, %{code: code} = reason} ->
          if code == ErrorCodes.plan_not_found(), do: {:error, Errors.plan_not_found(nil)}, else: {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end

    {result, state}
  end

  def run({:update_plan_status, plan_id, next_status, expected_revision, opts}, %State{} = state) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.revision_matches(plan, expected_revision),
           :ok <- StatusMachine.validate_plan_transition(Map.get(plan, Fields.status()), next_status),
           updated_plan <- Record.bump_plan(plan, opts) |> Map.put(Fields.status(), next_status),
           {:ok, valid_plan} <- Schema.validate(updated_plan),
           :ok <- ensure_active_slot_available(state, valid_plan, plan_id),
           {:ok, _agent_plan} <- Persistence.replace_projected_plan(state, valid_plan, expected_revision) do
        Persistence.put_plan(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run({:update_item_status, plan_id, item_id, next_status, expected_revision, opts}, %State{} = state) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           {:ok, item} <- fetch_item(plan, item_id),
           :ok <- StatusMachine.validate_item_transition(Map.get(item, AgentFields.status()), next_status),
           updated_plan <- Record.update_item(plan, item_id, Map.put(Record.bump_item(item, opts), AgentFields.status(), next_status), opts),
           {:ok, valid_plan} <- Schema.validate(updated_plan),
           {:ok, _agent_plan} <- Persistence.replace_projected_plan(state, valid_plan, expected_revision) do
        Persistence.put_plan(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run({:append_evidence_ref, plan_id, item_id, evidence_ref, expected_revision, opts}, %State{} = state) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           {:ok, item} <- fetch_item(plan, item_id),
           {:ok, scrubbed_evidence_ref} <- Scrubber.scrub_map(evidence_ref, opts),
           {:ok, updated_item} <- Evidence.append_ref(item, scrubbed_evidence_ref) do
        if updated_item == item do
          {:ok, state}
        else
          updated_plan = Record.update_item(plan, item_id, Record.bump_item(updated_item, opts), opts)

          with {:ok, valid_plan} <- Schema.validate(updated_plan),
               {:ok, _agent_plan} <- Persistence.replace_projected_plan(state, valid_plan, expected_revision) do
            Persistence.put_plan(state, valid_plan)
          end
        end
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run({:upsert_agent_items, plan_id, items, expected_revision, opts}, %State{} = state) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           :ok <- AgentOwnedItemPolicy.ensure_upsertable_items(items),
           {:ok, updated_plan} <- AgentOwnedItemPolicy.upsert(plan, items, opts),
           {:ok, valid_plan} <- Schema.validate(updated_plan),
           {:ok, _agent_plan} <- Persistence.replace_projected_plan(state, valid_plan, expected_revision) do
        Persistence.put_plan(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run({:record_evidence_refs, plan_id, evidence_refs, opts}, %State{} = state) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           {:ok, updated_plan} <- EvidenceRefs.record_and_reconcile(plan, evidence_refs, opts),
           {:ok, valid_plan} <- Schema.validate(updated_plan),
           {:ok, _agent_plan} <- Persistence.replace_projected_plan(state, valid_plan, Map.fetch!(plan, Fields.revision())) do
        Persistence.put_plan(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run({:record_render_marker, plan_id, marker, expected_revision}, %State{} = state) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           {:ok, valid_marker} <- Renderer.validate_marker(marker, plan) do
        updated_plan = Map.put(plan, Fields.rendering(), valid_marker)

        with {:ok, valid_plan} <- Schema.validate(updated_plan),
             {:ok, _agent_plan} <- Persistence.replace_projected_plan(state, valid_plan, expected_revision) do
          Persistence.put_plan(state, valid_plan)
        end
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run({:record_provider_session_event, plan_id, event, expected_revision, opts}, %State{} = state) do
    result =
      with {:ok, plan} <- Persistence.fetch(state, plan_id),
           :ok <- Guards.plan_mutable(plan),
           :ok <- Guards.revision_matches(plan, expected_revision),
           {:ok, scrubbed_event} <- Scrubber.scrub_map(event, opts),
           {:ok, valid_event} <- ProviderSessionEvent.validate(scrubbed_event),
           {:ok, updated_plan} <- ProviderSessionEvents.record(plan, valid_event, opts),
           {:ok, valid_plan} <- Schema.validate(updated_plan),
           {:ok, _agent_plan} <- Persistence.replace_projected_plan(state, valid_plan, expected_revision) do
        Persistence.put_plan(state, valid_plan)
      end

    reply_with_fetch(result, state, plan_id)
  end

  def run(:reset, %State{} = state) do
    case Persistence.reset(state) do
      {:ok, next_state} -> {:ok, next_state}
      {:error, _reason} -> {:ok, state}
    end
  end

  defp ensure_plan_id_available(%State{} = state, plan) do
    plan
    |> Map.fetch!(Fields.plan_id())
    |> then(&Persistence.fetch_envelope(state, &1))
    |> Guards.plan_id_available(plan)
  end

  defp ensure_active_slot_available(%State{} = state, plan, current_plan_id \\ nil) do
    active_result =
      if Map.get(plan, Fields.status()) == Contract.active_plan_status() do
        plan
        |> Persistence.active_key()
        |> then(&Persistence.active_plan_id(state, &1))
      else
        {:error, Errors.plan_not_found(nil)}
      end

    Guards.active_slot_available(active_result, plan, current_plan_id)
  end

  defp fetch_item(plan, item_id) do
    items = Map.fetch!(plan, Fields.items())

    case Enum.find(items, &(Map.get(&1, AgentFields.item_id()) == item_id)) do
      nil -> {:error, Errors.item_not_found(item_id)}
      item -> {:ok, item}
    end
  end

  defp reply_with_fetch({:ok, next_state}, _previous_state, plan_id), do: {Persistence.fetch(next_state, plan_id), next_state}
  defp reply_with_fetch({:error, reason}, previous_state, _plan_id), do: {{:error, reason}, previous_state}
end
