defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.MemoryBackend do
  @moduledoc """
  In-memory workflow execution-plan envelope backend.
  """

  @behaviour SymphonyElixir.Workflow.StructuredExecutionPlan.Storage

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.ActiveKey

  @default_max_records 10_000

  defstruct envelopes: %{},
            active_index: %{},
            max_records: @default_max_records

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       max_records: positive_integer(Keyword.get(opts, :max_records), @default_max_records)
     }}
  end

  @impl true
  def fetch_envelope(%__MODULE__{envelopes: envelopes}, plan_id) do
    case Map.fetch(envelopes, plan_id) do
      {:ok, envelope} -> {:ok, envelope}
      :error -> :error
    end
  end

  @impl true
  def put_envelope(%__MODULE__{} = state, envelope) do
    envelopes =
      state.envelopes
      |> Map.put(Map.fetch!(envelope, Fields.plan_id()), envelope)
      |> enforce_limit(state.max_records)

    {:ok, rebuild_active_index(%{state | envelopes: envelopes})}
  end

  @impl true
  def delete_envelope(%__MODULE__{} = state, plan_id) do
    {:ok, rebuild_active_index(%{state | envelopes: Map.delete(state.envelopes, plan_id)})}
  end

  @impl true
  def active_plan_id(%__MODULE__{active_index: active_index}, key) do
    case Map.fetch(active_index, key) do
      {:ok, plan_id} -> {:ok, plan_id}
      :error -> :error
    end
  end

  @impl true
  def list_plan_ids(%__MODULE__{envelopes: envelopes}) do
    {:ok, Map.keys(envelopes)}
  end

  @impl true
  def reset(%__MODULE__{} = state), do: {:ok, %{state | envelopes: %{}, active_index: %{}}}

  defp rebuild_active_index(%__MODULE__{} = state) do
    active_index =
      state.envelopes
      |> Map.values()
      |> Enum.filter(&ActiveKey.active?/1)
      |> Map.new(fn envelope -> {ActiveKey.from_envelope!(envelope), Map.fetch!(envelope, Fields.plan_id())} end)

    %{state | active_index: active_index}
  end

  defp enforce_limit(envelopes, max_records) when map_size(envelopes) <= max_records, do: envelopes

  defp enforce_limit(envelopes, max_records) do
    envelopes
    |> Enum.take(-max_records)
    |> Map.new()
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
