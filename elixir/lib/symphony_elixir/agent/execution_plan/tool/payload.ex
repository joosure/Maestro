defmodule SymphonyElixir.Agent.ExecutionPlan.Tool.Payload do
  @moduledoc """
  Stable payload wrappers for Agent execution-plan tool commands.

  Public tool arguments are string-key maps. `Tool.Arguments` turns those maps
  into command structs and wraps complex payloads here before the executor
  orchestrates Store calls.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Evidence
  alias SymphonyElixir.Agent.ExecutionPlan.Record
  alias SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRef, as: RecordEvidenceRef
  alias SymphonyElixir.Agent.ExecutionPlan.Schema

  defmodule Plan do
    @moduledoc false
    @enforce_keys [:record]
    defstruct [:record]

    @type t :: %__MODULE__{record: SymphonyElixir.Agent.ExecutionPlan.Record.Plan.t()}
  end

  defmodule ItemSet do
    @moduledoc false
    @enforce_keys [:items]
    defstruct [:items]

    @type t :: %__MODULE__{items: [map()]}
  end

  defmodule EvidenceRef do
    @moduledoc false
    @enforce_keys [:record]
    defstruct [:record]

    @type t :: %__MODULE__{record: SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRef.t()}
  end

  @spec plan(map()) :: {:ok, Plan.t()} | {:error, map()}
  def plan(plan) when is_map(plan) do
    with {:ok, record} <- Schema.normalize(plan) do
      {:ok, %Plan{record: record}}
    end
  end

  @spec item_set(term()) :: {:ok, ItemSet.t()} | {:error, term()}
  def item_set(items) when is_list(items) do
    if items != [] and Enum.all?(items, &is_map/1) do
      {:ok, %ItemSet{items: items}}
    else
      invalid_item_set()
    end
  end

  def item_set(_items), do: invalid_item_set()

  @spec evidence_ref(map()) :: {:ok, EvidenceRef.t()} | {:error, map()}
  def evidence_ref(ref) when is_map(ref) do
    with {:ok, valid_ref} <- Evidence.validate_ref(ref) do
      {:ok, %EvidenceRef{record: RecordEvidenceRef.from_map(valid_ref)}}
    end
  end

  @spec plan_map(Plan.t()) :: map()
  def plan_map(%Plan{record: record}), do: Record.to_map(record)

  @spec item_maps(ItemSet.t()) :: [map()]
  def item_maps(%ItemSet{items: items}), do: items

  @spec evidence_ref_map(EvidenceRef.t()) :: map()
  def evidence_ref_map(%EvidenceRef{record: record}), do: Record.to_map(record)

  defp invalid_item_set do
    {:error, {:invalid_arguments, "items must be a non-empty array of item objects."}}
  end
end
