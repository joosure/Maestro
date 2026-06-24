defmodule SymphonyElixir.Agent.ExecutionPlan.Record.SourcePlanRef do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions

  @type t :: %__MODULE__{
          artifact_id: String.t(),
          hash: String.t(),
          extensions: Extensions.t() | nil
        }

  defstruct artifact_id: nil,
            hash: nil,
            extensions: nil

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(ref) when is_map(ref) do
    %__MODULE__{
      artifact_id: Map.fetch!(ref, Fields.artifact_id()),
      hash: Map.fetch!(ref, Fields.hash()),
      extensions: Extensions.from_map(Map.get(ref, Fields.extensions()))
    }
  end
end

defmodule SymphonyElixir.Agent.ExecutionPlan.Record.Rendering do
  @moduledoc false

  @type t :: %__MODULE__{value: map()}

  defstruct value: %{}

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil
  def from_map(value) when is_map(value), do: %__MODULE__{value: value}
end

defmodule SymphonyElixir.Agent.ExecutionPlan.Record.StatusReason do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions

  @type t :: %__MODULE__{
          reason_code: String.t(),
          actor: String.t() | nil,
          evidence_id: String.t() | nil,
          message: String.t() | nil,
          extensions: Extensions.t() | nil
        }

  defstruct reason_code: nil,
            actor: nil,
            evidence_id: nil,
            message: nil,
            extensions: nil

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(reason) when is_map(reason) do
    %__MODULE__{
      reason_code: Map.fetch!(reason, Fields.reason_code()),
      actor: Map.get(reason, Fields.actor()),
      evidence_id: Map.get(reason, Fields.evidence_id()),
      message: Map.get(reason, Fields.message()),
      extensions: Extensions.from_map(Map.get(reason, Fields.extensions()))
    }
  end
end

defmodule SymphonyElixir.Agent.ExecutionPlan.Record.Matcher do
  @moduledoc false

  @type t :: %__MODULE__{value: map()}

  defstruct value: %{}

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil
  def from_map(value) when is_map(value), do: %__MODULE__{value: value}
end

defmodule SymphonyElixir.Agent.ExecutionPlan.Record.Extensions do
  @moduledoc false

  @type t :: %__MODULE__{value: map()}

  defstruct value: %{}

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil
  def from_map(value) when is_map(value), do: %__MODULE__{value: value}
end
