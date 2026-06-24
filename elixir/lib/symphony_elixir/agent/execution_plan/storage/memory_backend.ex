defmodule SymphonyElixir.Agent.ExecutionPlan.Storage.MemoryBackend do
  @moduledoc """
  In-memory Agent execution-plan storage backend.

  This backend is intended for tests and explicitly non-durable local runs.
  """

  @behaviour SymphonyElixir.Agent.ExecutionPlan.Storage

  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  @default_max_records 10_000

  defstruct plans: %{},
            max_records: @default_max_records

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       max_records: positive_integer(Keyword.get(opts, :max_records), @default_max_records)
     }}
  end

  @impl true
  def fetch_plan(%__MODULE__{plans: plans}, plan_id) do
    case Map.fetch(plans, plan_id) do
      {:ok, plan} -> {:ok, plan}
      :error -> :error
    end
  end

  @impl true
  def put_plan(%__MODULE__{} = state, plan) do
    plans =
      state.plans
      |> Map.put(Map.fetch!(plan, Fields.plan_id()), plan)
      |> enforce_limit(state.max_records)

    {:ok, %{state | plans: plans}}
  end

  @impl true
  def delete_plan(%__MODULE__{} = state, plan_id), do: {:ok, %{state | plans: Map.delete(state.plans, plan_id)}}

  @impl true
  def reset(%__MODULE__{} = state), do: {:ok, %{state | plans: %{}}}

  defp enforce_limit(plans, max_records) when map_size(plans) <= max_records, do: plans

  defp enforce_limit(plans, max_records) do
    plans
    |> Enum.take(-max_records)
    |> Map.new()
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
