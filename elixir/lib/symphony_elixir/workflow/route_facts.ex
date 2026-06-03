defmodule SymphonyElixir.Workflow.RouteFacts do
  @moduledoc """
  Resolved route facts for an issue's current tracker state.
  """

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RoutePolicy.Policy

  @enforce_keys [:route_key, :raw_state, :lifecycle_phase, :policy, :action]
  defstruct [
    :route_key,
    :raw_state,
    :lifecycle_phase,
    :policy,
    :action,
    :transition_target,
    :execution_profile
  ]

  @type t :: %__MODULE__{
          route_key: atom(),
          raw_state: String.t(),
          lifecycle_phase: String.t() | nil,
          policy: Policy.t(),
          action: atom(),
          transition_target: atom() | nil,
          execution_profile: String.t() | nil
        }

  @spec from_fields(map()) :: t() | nil
  def from_fields(attrs) when is_map(attrs) do
    raw_state_by_route_key = Map.get(attrs, :raw_state_by_route_key)
    profile_module = Map.fetch!(attrs, :profile_module)
    state = Map.get(attrs, :state)

    with true <- is_map(raw_state_by_route_key) and map_size(raw_state_by_route_key) > 0,
         route_key when is_atom(route_key) <-
           RoutePolicy.route_key_for_raw_state(state, raw_state_by_route_key, profile_module),
         raw_state when is_binary(raw_state) <-
           RoutePolicy.raw_state_for_route_key(raw_state_by_route_key, route_key) do
      policy =
        attrs
        |> Map.get(:policy_by_route_key)
        |> route_policy_for(route_key)
        |> Policy.new!()

      new!(%{
        route_key: route_key,
        raw_state: raw_state,
        lifecycle_phase: Map.get(attrs, :lifecycle_phase) || resolved_lifecycle_phase(attrs, raw_state),
        policy: policy,
        action: policy.action,
        transition_target: policy.transition_target,
        execution_profile: policy.execution_profile
      })
    else
      _other -> nil
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)

  @spec policy_map(t()) :: map()
  def policy_map(%__MODULE__{policy: %Policy{} = policy}), do: Policy.to_map(policy)

  defp route_policy_for(policy_by_route_key, route_key) do
    case RoutePolicy.policy_for_route_key(policy_by_route_key, route_key) do
      policy when is_map(policy) and map_size(policy) > 0 -> policy
      _policy -> %{action: :dispatch}
    end
  end

  defp resolved_lifecycle_phase(attrs, raw_state) when is_map(attrs) do
    raw_state
    |> WorkflowLifecycle.phase_for_state(Map.get(attrs, :state_phase_map, %{}))
  end
end
