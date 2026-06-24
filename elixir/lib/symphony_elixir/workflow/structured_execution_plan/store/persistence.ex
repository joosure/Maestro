defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Persistence do
  @moduledoc """
  Persistence boundary for workflow structured-plan Store commands.

  Workflow structured plans are reconstructed from workflow adoption envelopes
  plus generic Agent execution plans. This module owns those persistence
  reads/writes and process-state initialization. It does not own workflow
  mutation policy, evidence matching, or provider-session event immutability.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Store, as: AgentStore
  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjection
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.Config, as: WorkflowStorageConfig
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Errors
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Server.State

  @spec init(keyword()) :: {:ok, State.t()} | {:error, term()}
  def init(opts) do
    backend = WorkflowStorageConfig.backend(opts)

    with {:ok, agent_store} <- agent_store(opts),
         {:ok, backend_state} <- backend.init(opts) do
      {:ok, %State{backend: backend, backend_state: backend_state, agent_store: agent_store}}
    end
  end

  @spec fetch(State.t(), String.t()) :: {:ok, map()} | {:error, map()}
  def fetch(%State{} = state, plan_id) when is_binary(plan_id) do
    with {:ok, envelope} <- fetch_envelope(state, plan_id),
         {:ok, agent_plan} <- AgentStore.fetch(plan_id, server: state.agent_store) do
      {:ok, AgentPlanProjection.from_agent_plan(agent_plan, envelope)}
    end
  end

  @spec fetch_envelope(State.t(), String.t()) :: {:ok, map()} | {:error, map()}
  def fetch_envelope(%State{backend: backend, backend_state: backend_state}, plan_id) when is_binary(plan_id) do
    case backend.fetch_envelope(backend_state, plan_id) do
      {:ok, envelope} -> {:ok, envelope}
      :error -> {:error, Errors.plan_not_found(plan_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec create_projected_plan(State.t(), map()) :: {:ok, map()} | {:error, map()}
  def create_projected_plan(%State{} = state, plan) when is_map(plan) do
    AgentStore.create(AgentPlanProjection.to_agent_plan(plan), server: state.agent_store, preserve_metadata?: true)
  end

  @spec replace_projected_plan(State.t(), map(), pos_integer()) :: {:ok, map()} | {:error, map()}
  def replace_projected_plan(%State{} = state, plan, expected_revision) when is_map(plan) do
    AgentStore.replace(
      Map.fetch!(plan, Fields.plan_id()),
      AgentPlanProjection.to_agent_plan(plan),
      expected_revision,
      server: state.agent_store,
      preserve_metadata?: true
    )
  end

  @spec put_plan(State.t(), map()) :: {:ok, State.t()} | {:error, term()}
  def put_plan(%State{backend: backend, backend_state: backend_state} = state, plan) when is_map(plan) do
    case backend.put_envelope(backend_state, AgentPlanProjection.envelope(plan)) do
      {:ok, next_backend_state} -> {:ok, %{state | backend_state: next_backend_state}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec active_key(map()) :: term()
  def active_key(plan) when is_map(plan) do
    active_key(Map.fetch!(plan, Fields.run_id()), Map.fetch!(plan, Fields.workflow_profile()), Map.fetch!(plan, Fields.route_key()))
  end

  @spec active_key(String.t(), map(), String.t()) :: term()
  def active_key(run_id, workflow_profile, route_key)
      when is_binary(run_id) and is_map(workflow_profile) and is_binary(route_key) do
    case RouteRef.storage_key(run_id, workflow_profile, route_key) do
      {:ok, active_key} -> active_key
      {:error, reason} -> raise ArgumentError, "invalid structured plan route ref: #{inspect(reason)}"
    end
  end

  @spec active_plan_id(State.t(), term()) :: {:ok, String.t()} | {:error, map() | term()}
  def active_plan_id(%State{backend: backend, backend_state: backend_state}, key) do
    case backend.active_plan_id(backend_state, key) do
      {:ok, plan_id} -> {:ok, plan_id}
      :error -> {:error, Errors.plan_not_found(nil)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reset(State.t()) :: {:ok, State.t()} | {:error, term()}
  def reset(%State{} = state) do
    case list_plan_ids(state) do
      {:ok, plan_ids} ->
        Enum.each(plan_ids, &AgentStore.delete(&1, server: state.agent_store))

      {:error, _reason} ->
        :ok
    end

    reset_storage(state)
  end

  defp list_plan_ids(%State{backend: backend, backend_state: backend_state}) do
    backend.list_plan_ids(backend_state)
  end

  defp reset_storage(%State{backend: backend, backend_state: backend_state} = state) do
    case backend.reset(backend_state) do
      {:ok, next_backend_state} -> {:ok, %{state | backend_state: next_backend_state}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp agent_store(opts) do
    case Keyword.fetch(opts, :agent_store) do
      {:ok, store} ->
        {:ok, store}

      :error ->
        case Keyword.get(opts, :agent_store_mode, :shared) do
          :local ->
            opts
            |> Keyword.take([:backend, :repo, :max_records])
            |> Keyword.put(:name, nil)
            |> AgentStore.start_link()

          _mode ->
            {:ok, AgentStore}
        end
    end
  end
end
