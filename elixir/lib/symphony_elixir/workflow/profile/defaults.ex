defmodule SymphonyElixir.Workflow.Profile.Defaults do
  @moduledoc """
  Profile-owned defaults after profile options have been applied.

  Raw tracker state mappings are intentionally excluded: they belong to
  workflow config and tracker adapters, not profile semantics.
  """

  @enforce_keys [
    :route_keys,
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
