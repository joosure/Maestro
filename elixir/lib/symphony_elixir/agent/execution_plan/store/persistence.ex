defmodule SymphonyElixir.Agent.ExecutionPlan.Store.Persistence do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Record
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Plan
  alias SymphonyElixir.Agent.ExecutionPlan.Schema
  alias SymphonyElixir.Agent.ExecutionPlan.Storage.Config, as: StorageConfig
  alias SymphonyElixir.Agent.ExecutionPlan.Store.ErrorResults
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Server.State

  @spec init(keyword()) :: {:ok, State.t()} | {:error, term()}
  def init(opts) do
    backend = StorageConfig.backend(opts)

    with {:ok, backend_state} <- backend.init(opts) do
      {:ok, %State{backend: backend, backend_state: backend_state}}
    end
  end

  @spec fetch(State.t(), String.t()) :: {:ok, Plan.t()} | {:error, map()}
  def fetch(%State{backend: backend, backend_state: backend_state}, plan_id) do
    case backend.fetch_plan(backend_state, plan_id) do
      {:ok, plan} -> Schema.normalize(plan)
      :error -> {:error, ErrorResults.plan_not_found(plan_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec put(State.t(), Plan.t()) :: {:ok, State.t()} | {:error, term()}
  def put(%State{backend: backend, backend_state: backend_state} = state, %Plan{} = plan) do
    case backend.put_plan(backend_state, Record.to_map(plan)) do
      {:ok, next_backend_state} -> {:ok, %{state | backend_state: next_backend_state}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete(State.t(), String.t()) :: {:ok, State.t()} | {:error, term()}
  def delete(%State{backend: backend, backend_state: backend_state} = state, plan_id) do
    case backend.delete_plan(backend_state, plan_id) do
      {:ok, next_backend_state} -> {:ok, %{state | backend_state: next_backend_state}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reset(State.t()) :: {:ok, State.t()} | {:error, term()}
  def reset(%State{backend: backend, backend_state: backend_state} = state) do
    case backend.reset(backend_state) do
      {:ok, next_backend_state} -> {:ok, %{state | backend_state: next_backend_state}}
      {:error, reason} -> {:error, reason}
    end
  end
end
