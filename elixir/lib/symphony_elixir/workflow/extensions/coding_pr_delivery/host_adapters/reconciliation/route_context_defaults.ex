defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.RouteContextDefaults do
  @moduledoc false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Workflow.ProfileRegistry

  @spec resolve_profile!(map()) :: ProfileRegistry.resolved_profile()
  def resolve_profile!(profile), do: ProfileRegistry.resolve!(profile)

  @spec default_policy_by_route_key(map()) :: map()
  def default_policy_by_route_key(%{module: module} = profile_context) do
    options = Map.get(profile_context, :options, %{})
    ProfileRegistry.default_policy_by_route_key(module, options)
  end

  @spec state_phase_map(map()) :: map() | nil
  def state_phase_map(tracker), do: TrackerConfig.state_phase_map(tracker)

  @spec workflows_by_type(map()) :: map() | nil
  def workflows_by_type(tracker), do: TrackerConfig.workflows_by_type(tracker)

  @spec workflow_raw_state_by_route_key(map()) :: map() | nil
  def workflow_raw_state_by_route_key(workflow), do: TrackerConfig.workflow_raw_state_by_route_key(workflow)

  @spec raw_state_by_route_key(map()) :: map() | nil
  def raw_state_by_route_key(tracker), do: TrackerConfig.raw_state_by_route_key(tracker)

  @spec policy_by_route_key(map()) :: map() | nil
  def policy_by_route_key(tracker), do: TrackerConfig.policy_by_route_key(tracker)
end
