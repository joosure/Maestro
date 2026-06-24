defmodule SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRequirement do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Matcher

  @type t :: %__MODULE__{
          evidence_kind: String.t(),
          required: boolean() | nil,
          required_fields: [String.t()],
          trust_classes: [String.t()],
          matcher: Matcher.t() | nil,
          extensions: Extensions.t() | nil
        }

  defstruct evidence_kind: nil,
            required: nil,
            required_fields: [],
            trust_classes: [],
            matcher: nil,
            extensions: nil

  @spec from_map(map()) :: t()
  def from_map(requirement) when is_map(requirement) do
    %__MODULE__{
      evidence_kind: Map.fetch!(requirement, Fields.evidence_kind()),
      required: Map.get(requirement, Fields.required()),
      required_fields: Map.fetch!(requirement, Fields.required_fields()),
      trust_classes: Map.fetch!(requirement, Fields.trust_classes()),
      matcher: Matcher.from_map(Map.get(requirement, Fields.matcher())),
      extensions: Extensions.from_map(Map.get(requirement, Fields.extensions()))
    }
  end
end

defmodule SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRef do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions

  @type t :: %__MODULE__{
          evidence_id: String.t(),
          evidence_kind: String.t(),
          source: String.t(),
          producer: String.t(),
          context_key: String.t() | nil,
          run_id: String.t() | nil,
          task_id: String.t() | nil,
          observed_at: String.t(),
          payload: map(),
          extensions: Extensions.t() | nil
        }

  defstruct evidence_id: nil,
            evidence_kind: nil,
            source: nil,
            producer: nil,
            context_key: nil,
            run_id: nil,
            task_id: nil,
            observed_at: nil,
            payload: nil,
            extensions: nil

  @spec from_map(map()) :: t()
  def from_map(ref) when is_map(ref) do
    %__MODULE__{
      evidence_id: Map.fetch!(ref, Fields.evidence_id()),
      evidence_kind: Map.fetch!(ref, Fields.evidence_kind()),
      source: Map.fetch!(ref, Fields.source()),
      producer: Map.fetch!(ref, Fields.producer()),
      context_key: Map.get(ref, Fields.evidence_context_key()),
      run_id: Map.get(ref, Fields.run_id()),
      task_id: Map.get(ref, Fields.task_id()),
      observed_at: Map.fetch!(ref, Fields.observed_at()),
      payload: Map.fetch!(ref, Fields.payload()),
      extensions: Extensions.from_map(Map.get(ref, Fields.extensions()))
    }
  end
end
