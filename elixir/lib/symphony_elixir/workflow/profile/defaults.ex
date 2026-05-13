defmodule SymphonyElixir.Workflow.Profile.Defaults do
  @moduledoc """
  Profile-owned defaults after profile options have been applied.

  Tracker adapters may override raw tracker state mappings, but this struct is
  the profile contract that Workflow Core validates against.
  """

  @enforce_keys [
    :route_keys,
    :raw_state_by_route_key,
    :policy_by_route_key,
    :lifecycle_phase_by_route_key,
    :completion_contract,
    :allowed_execution_profiles,
    :required_capabilities,
    :optional_capabilities
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          route_keys: [atom()],
          raw_state_by_route_key: map(),
          policy_by_route_key: map(),
          lifecycle_phase_by_route_key: map(),
          completion_contract: map(),
          allowed_execution_profiles: [String.t()],
          required_capabilities: [String.t()],
          optional_capabilities: [String.t()]
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = defaults), do: Map.from_struct(defaults)
end
