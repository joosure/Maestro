defmodule SymphonyElixir.Agent.ExecutionPlan.Record.WorkflowRef do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  @type t :: %__MODULE__{
          profile_kind: String.t() | nil,
          profile_version: pos_integer() | nil,
          route_key: String.t() | nil,
          lifecycle_phase: String.t() | nil,
          issue_id: String.t() | nil,
          issue_identifier: String.t() | nil,
          tracker_kind: String.t() | nil
        }

  defstruct profile_kind: nil,
            profile_version: nil,
            route_key: nil,
            lifecycle_phase: nil,
            issue_id: nil,
            issue_identifier: nil,
            tracker_kind: nil

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(ref) when is_map(ref) do
    %__MODULE__{
      profile_kind: Map.get(ref, Fields.profile_kind()),
      profile_version: Map.get(ref, Fields.profile_version()),
      route_key: Map.get(ref, Fields.route_key()),
      lifecycle_phase: Map.get(ref, Fields.lifecycle_phase()),
      issue_id: Map.get(ref, Fields.issue_id()),
      issue_identifier: Map.get(ref, Fields.issue_identifier()),
      tracker_kind: Map.get(ref, Fields.tracker_kind())
    }
  end
end

defmodule SymphonyElixir.Agent.ExecutionPlan.Record.RepoRef do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  @type t :: %__MODULE__{
          provider: String.t() | nil,
          repository_id: String.t() | nil,
          branch: String.t() | nil
        }

  defstruct provider: nil,
            repository_id: nil,
            branch: nil

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(ref) when is_map(ref) do
    %__MODULE__{
      provider: Map.get(ref, Fields.provider()),
      repository_id: Map.get(ref, Fields.repository_id()),
      branch: Map.get(ref, Fields.branch())
    }
  end
end

defmodule SymphonyElixir.Agent.ExecutionPlan.Record.TrackerRef do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  @type t :: %__MODULE__{
          tracker_kind: String.t() | nil,
          issue_id: String.t() | nil,
          issue_identifier: String.t() | nil
        }

  defstruct tracker_kind: nil,
            issue_id: nil,
            issue_identifier: nil

  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(ref) when is_map(ref) do
    %__MODULE__{
      tracker_kind: Map.get(ref, Fields.tracker_kind()),
      issue_id: Map.get(ref, Fields.issue_id()),
      issue_identifier: Map.get(ref, Fields.issue_identifier())
    }
  end
end
