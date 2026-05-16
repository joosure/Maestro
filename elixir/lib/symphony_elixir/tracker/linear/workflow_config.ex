defmodule SymphonyElixir.Tracker.Linear.WorkflowConfig do
  @moduledoc false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Workflow.Effective
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy

  @coding_raw_state_by_route_key %{
    planning: "Todo",
    developing: "In Progress",
    review: "In Review",
    merging: "Merging",
    rework: "Rework",
    resolved: "Done",
    rejected: "Canceled"
  }

  @spec workflow_profile(map()) :: map()
  def workflow_profile(tracker) when is_map(tracker) do
    tracker
    |> lifecycle_map()
    |> map_field(:workflow_profile)
    |> ProfileRegistry.normalize_config()
  end

  def workflow_profile(_tracker), do: ProfileRegistry.default_profile_config()

  @spec profile_context(map()) :: ProfileRegistry.resolved_profile()
  def profile_context(tracker) when is_map(tracker) do
    case ProfileRegistry.resolve(workflow_profile(tracker)) do
      {:ok, resolved_profile} -> resolved_profile
      {:error, _reason} -> ProfileRegistry.resolve!(nil)
    end
  end

  def profile_context(_tracker), do: ProfileRegistry.resolve!(nil)

  @spec global_workflow(map()) :: Effective.t()
  def global_workflow(tracker) when is_map(tracker) do
    profile_context = profile_context(tracker)
    profile_module = profile_context.module
    profile_options = profile_context.options
    lifecycle = lifecycle_map(tracker)

    %{
      workitem_type_id: nil,
      active_states: List.wrap(TrackerConfig.active_states(tracker)),
      terminal_states: List.wrap(TrackerConfig.terminal_states(tracker)),
      state_phase_map:
        tracker
        |> TrackerConfig.state_phase_map()
        |> case do
          state_phase_map when is_map(state_phase_map) -> WorkflowLifecycle.normalize_state_phase_map(state_phase_map)
          _state_phase_map -> %{}
        end,
      raw_state_by_route_key:
        lifecycle
        |> map_field(:raw_state_by_route_key)
        |> resolve_raw_state_by_route_key(default_raw_state_by_route_key(profile_context), profile_module),
      policy_by_route_key:
        lifecycle
        |> map_field(:policy_by_route_key)
        |> RoutePolicy.resolve_policy_by_route_key(
          ProfileRegistry.default_policy_by_route_key(profile_module, profile_options),
          profile_module
        )
    }
    |> Map.merge(workflow_facts(profile_context))
    |> Effective.new!()
  end

  @spec default_raw_state_by_route_key(ProfileRegistry.resolved_profile()) :: map()
  def default_raw_state_by_route_key(%{kind: "coding_pr_delivery"}), do: @coding_raw_state_by_route_key
  def default_raw_state_by_route_key(%{module: profile_module}), do: profile_module.default_raw_state_by_route_key()

  @spec resolve_raw_state_by_route_key(map() | nil, map(), module()) :: map()
  def resolve_raw_state_by_route_key(raw_state_by_route_key, base_raw_state_by_route_key, profile_module)
      when is_map(base_raw_state_by_route_key) and is_atom(profile_module) do
    Enum.reduce(profile_module.route_keys(), base_raw_state_by_route_key, fn route_key, acc ->
      case raw_state_by_route_key |> map_field(route_key) |> normalize_string() do
        nil -> acc
        raw_state -> Map.put(acc, route_key, raw_state)
      end
    end)
  end

  defp workflow_facts(%{kind: kind, version: version, options: options, module: profile_module} = profile_context) do
    %{
      profile: %{kind: kind, version: version, options: options},
      profile_kind: kind,
      profile_version: version,
      profile_options: options,
      allowed_execution_profiles: ExecutionProfileRegistry.effective_allowed_execution_profiles(profile_context),
      completion_contract: ProfileRegistry.completion_contract(profile_module, options),
      required_capabilities: ProfileRegistry.required_capabilities(profile_module, options),
      optional_capabilities: ProfileRegistry.optional_capabilities(profile_module, options)
    }
  end

  defp lifecycle_map(tracker) when is_map(tracker) do
    TrackerConfig.lifecycle(tracker)
  end

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(_value), do: nil
end
