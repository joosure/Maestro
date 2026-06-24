defmodule SymphonyElixir.Agent.ExecutionPlan.Record.Item do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRequirement
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions
  alias SymphonyElixir.Agent.ExecutionPlan.Record.StatusReason

  @type t :: %__MODULE__{
          item_id: String.t(),
          parent_item_id: String.t() | nil,
          title: String.t(),
          kind: String.t(),
          status: String.t(),
          required: boolean(),
          criticality: String.t(),
          owned_by: String.t(),
          source: String.t(),
          depends_on: [String.t()],
          evidence_requirements: [EvidenceRequirement.t()],
          evidence_refs: [EvidenceRef.t()],
          status_reason: StatusReason.t() | nil,
          extensions: Extensions.t() | nil,
          created_at: String.t(),
          updated_at: String.t(),
          revision: pos_integer()
        }

  defstruct item_id: nil,
            parent_item_id: nil,
            title: nil,
            kind: nil,
            status: nil,
            required: nil,
            criticality: nil,
            owned_by: nil,
            source: nil,
            depends_on: [],
            evidence_requirements: [],
            evidence_refs: [],
            status_reason: nil,
            extensions: nil,
            created_at: nil,
            updated_at: nil,
            revision: nil

  @spec from_map(map()) :: t()
  def from_map(item) when is_map(item) do
    %__MODULE__{
      item_id: Map.fetch!(item, Fields.item_id()),
      parent_item_id: Map.get(item, Fields.parent_item_id()),
      title: Map.fetch!(item, Fields.title()),
      kind: Map.fetch!(item, Fields.kind()),
      status: Map.fetch!(item, Fields.status()),
      required: Map.fetch!(item, Fields.required()),
      criticality: Map.fetch!(item, Fields.criticality()),
      owned_by: Map.fetch!(item, Fields.owned_by()),
      source: Map.fetch!(item, Fields.source()),
      depends_on: Map.fetch!(item, Fields.depends_on()),
      evidence_requirements: item |> Map.fetch!(Fields.evidence_requirements()) |> Enum.map(&EvidenceRequirement.from_map/1),
      evidence_refs: item |> Map.fetch!(Fields.evidence_refs()) |> Enum.map(&EvidenceRef.from_map/1),
      status_reason: StatusReason.from_map(Map.get(item, Fields.status_reason())),
      extensions: Extensions.from_map(Map.get(item, Fields.extensions())),
      created_at: Map.fetch!(item, Fields.created_at()),
      updated_at: Map.fetch!(item, Fields.updated_at()),
      revision: Map.fetch!(item, Fields.revision())
    }
  end
end
