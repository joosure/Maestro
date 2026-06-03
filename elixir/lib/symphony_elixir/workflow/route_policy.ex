defmodule SymphonyElixir.Workflow.RoutePolicy do
  @moduledoc """
  Route-policy helpers for workflow-profile route actions.

  Route keys are Symphony workflow-profile vocabulary. Raw tracker states live in
  `raw_state_by_route_key`, and lifecycle phases live in `state_phase_map`.

  Boundary rule:

  - `resolve_*` functions consume raw workflow configuration from settings,
    `WORKFLOW.md`, or `workflows_by_type`.
  - `merge_effective_*`, `policy_for_route_key/2`, `raw_state_for_route_key/2`,
    and `disabled_route?/2` consume canonical effective workflow facts.
  - `issue.workflow` is an effective facts map. Callers that read
    `issue.workflow` must use the effective APIs and must not pass those maps
    through raw configuration resolvers.
  """

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy.Keys

  @action_by_name %{
    "dispatch" => :dispatch,
    "wait" => :wait,
    "stop" => :stop,
    "transition" => :transition,
    "transition_then_dispatch" => :transition_then_dispatch,
    "disabled" => :disabled
  }
  @transition_action_names ["transition", "transition_then_dispatch"]
  @actions @action_by_name |> Map.values() |> MapSet.new()
  @transition_actions @transition_action_names |> Enum.map(&Map.fetch!(@action_by_name, &1)) |> MapSet.new()

  @spec default_policy_by_route_key(module()) :: map()
  def default_policy_by_route_key(profile_module \\ ProfileRegistry.default_profile_module()) do
    profile_module.default_policy_by_route_key()
  end

  @spec expected_lifecycle_phases(module()) :: map()
  def expected_lifecycle_phases(profile_module \\ ProfileRegistry.default_profile_module()) do
    profile_module.lifecycle_phase_by_route_key()
  end

  @spec expected_lifecycle_phase(term(), module()) :: String.t() | nil
  def expected_lifecycle_phase(route_key, profile_module \\ ProfileRegistry.default_profile_module()) do
    route_key
    |> normalize_route_key(profile_module)
    |> then(&Map.get(expected_lifecycle_phases(profile_module), &1))
  end

  @spec route_keys(module()) :: [atom()]
  def route_keys(profile_module \\ ProfileRegistry.default_profile_module()) do
    Keys.route_keys(profile_module)
  end

  @doc """
  Builds a route-key identity raw-state map for in-memory/internal workflows.

  External tracker adapters should treat this only as a fallback when their
  workflow config has not provided explicit raw tracker statuses.
  """
  @spec identity_raw_state_by_route_key(module()) :: map()
  def identity_raw_state_by_route_key(profile_module \\ ProfileRegistry.default_profile_module()) do
    profile_module
    |> route_keys()
    |> Map.new(&{&1, Atom.to_string(&1)})
  end

  @doc """
  Resolves raw workflow-config raw-state overrides into an effective raw-state map.

  The returned map is keyed by profile route atoms. Raw override maps come from
  config files and must use external string keys before this boundary.
  """
  @spec resolve_raw_state_by_route_key(map() | nil, map() | nil, module()) :: map()
  def resolve_raw_state_by_route_key(
        raw_state_by_route_key,
        base_raw_state_by_route_key \\ nil,
        profile_module \\ ProfileRegistry.default_profile_module()
      ) do
    resolve_raw_state_by_route_key(raw_state_by_route_key, base_raw_state_by_route_key, profile_module, %{})
  end

  @spec resolve_raw_state_by_route_key(map() | nil, map() | nil, module(), map()) :: map()
  def resolve_raw_state_by_route_key(raw_state_by_route_key, base_raw_state_by_route_key, profile_module, policy_by_route_key)
      when is_atom(profile_module) do
    base_raw_state_by_route_key
    |> normalize_effective_raw_state_by_route_key(profile_module)
    |> merge_raw_config_state_by_route_key(raw_state_by_route_key, profile_module)
    |> remove_disabled_raw_states(policy_by_route_key, profile_module)
  end

  @doc """
  Overlays an effective raw-state map onto an effective base map.

  Both maps are runtime facts and must be keyed by profile route atoms.
  """
  @spec merge_effective_raw_state_by_route_key(map() | nil, map() | nil, module()) :: map()
  def merge_effective_raw_state_by_route_key(
        raw_state_by_route_key,
        base_raw_state_by_route_key \\ nil,
        profile_module \\ ProfileRegistry.default_profile_module()
      ) do
    merge_effective_raw_state_by_route_key(raw_state_by_route_key, base_raw_state_by_route_key, profile_module, %{})
  end

  @spec merge_effective_raw_state_by_route_key(map() | nil, map() | nil, module(), map()) :: map()
  def merge_effective_raw_state_by_route_key(raw_state_by_route_key, base_raw_state_by_route_key, profile_module, policy_by_route_key)
      when is_atom(profile_module) do
    base_raw_state_by_route_key
    |> normalize_effective_raw_state_by_route_key(profile_module)
    |> overlay_effective_raw_state_by_route_key(raw_state_by_route_key, profile_module)
    |> remove_disabled_raw_states(policy_by_route_key, profile_module)
  end

  @spec route_key?(term(), module()) :: boolean()
  def route_key?(route_key, profile_module \\ ProfileRegistry.default_profile_module()),
    do: Keys.route_key?(route_key, profile_module)

  @doc """
  Resolves raw workflow-config route-policy overrides into an effective policy map.

  The returned map is keyed by profile route atoms and is the only shape accepted
  by runtime policy lookups such as `policy_for_route_key/2` and
  `disabled_route?/2`. Raw override maps come from config files and use string
  route keys after input normalization.
  """
  @spec resolve_policy_by_route_key(map() | nil, map() | nil, module()) :: map()
  def resolve_policy_by_route_key(
        policy_by_route_key,
        base_policy_by_route_key \\ default_policy_by_route_key(),
        profile_module \\ ProfileRegistry.default_profile_module()
      ) do
    base_policy_by_route_key
    |> normalize_policy_by_route_key(profile_module)
    |> merge_policy_by_route_key(policy_by_route_key, profile_module)
  end

  @doc """
  Overlays an effective route-policy map onto an effective base map.

  Both maps are runtime facts and must be keyed by profile route atoms. This is
  intentionally separate from `resolve_policy_by_route_key/3`, which parses raw
  workflow config overrides from string-keyed input.
  """
  @spec merge_effective_policy_by_route_key(map() | nil, map() | nil, module()) :: map()
  def merge_effective_policy_by_route_key(
        policy_by_route_key,
        base_policy_by_route_key \\ default_policy_by_route_key(),
        profile_module \\ ProfileRegistry.default_profile_module()
      ) do
    base_policy_by_route_key
    |> normalize_policy_by_route_key(profile_module)
    |> overlay_effective_policy_by_route_key(policy_by_route_key, profile_module)
  end

  @spec route_key_for_raw_state(term(), map() | nil, module()) :: atom() | nil
  def route_key_for_raw_state(state_name, raw_state_by_route_key, profile_module \\ ProfileRegistry.default_profile_module())

  def route_key_for_raw_state(state_name, raw_state_by_route_key, profile_module) when is_map(raw_state_by_route_key) do
    normalized_state = WorkflowLifecycle.normalize_tracker_state(state_name)

    Enum.find(route_keys(profile_module), fn route_key ->
      case raw_state_for_route_key(raw_state_by_route_key, route_key) do
        raw_state when is_binary(raw_state) ->
          WorkflowLifecycle.normalize_tracker_state(raw_state) == normalized_state

        _ ->
          false
      end
    end)
  end

  def route_key_for_raw_state(_state_name, _raw_state_by_route_key, _profile_module), do: nil

  @spec valid_action?(term()) :: boolean()
  def valid_action?(action) when is_atom(action), do: MapSet.member?(@actions, action)
  def valid_action?(_action), do: false

  @spec transition_action?(term()) :: boolean()
  def transition_action?(action) when is_atom(action), do: MapSet.member?(@transition_actions, action)
  def transition_action?(_action), do: false

  @spec normalize_action(term()) :: atom() | nil
  def normalize_action(action_name) when is_atom(action_name) do
    action_name
    |> Atom.to_string()
    |> normalize_action()
  end

  def normalize_action(action_name) when is_binary(action_name) do
    @action_by_name
    |> Map.get(normalize_name(action_name))
  end

  def normalize_action(_action_name), do: nil

  @spec normalize_route_key(term(), module()) :: atom() | nil
  def normalize_route_key(route_key, profile_module \\ ProfileRegistry.default_profile_module())

  def normalize_route_key(route_key, profile_module), do: Keys.normalize_route_key(route_key, profile_module)

  @spec raw_state_for_route_key(map(), atom()) :: String.t() | nil
  def raw_state_for_route_key(raw_state_by_route_key, route_key) when is_map(raw_state_by_route_key) and is_atom(route_key) do
    raw_state_by_route_key
    |> Map.get(route_key)
    |> normalize_raw_state()
  end

  def raw_state_for_route_key(_raw_state_by_route_key, _route_key), do: nil

  @spec policy_for_route_key(map(), atom()) :: map()
  def policy_for_route_key(policy_by_route_key, route_key) when is_map(policy_by_route_key) and is_atom(route_key) do
    Map.get(policy_by_route_key, route_key, %{})
  end

  def policy_for_route_key(_policy_by_route_key, _route_key), do: %{}

  @spec disabled_route?(map(), atom()) :: boolean()
  def disabled_route?(policy_by_route_key, route_key) when is_map(policy_by_route_key) and is_atom(route_key) do
    policy_by_route_key
    |> policy_for_route_key(route_key)
    |> Map.get(:action)
    |> Kernel.==(:disabled)
  end

  def disabled_route?(_policy_by_route_key, _route_key), do: false

  @spec remove_disabled_raw_states(map(), map(), module()) :: map()
  def remove_disabled_raw_states(
        raw_state_by_route_key,
        policy_by_route_key,
        profile_module \\ ProfileRegistry.default_profile_module()
      )

  def remove_disabled_raw_states(raw_state_by_route_key, policy_by_route_key, profile_module)
      when is_map(raw_state_by_route_key) and is_map(policy_by_route_key) and is_atom(profile_module) do
    Enum.reduce(route_keys(profile_module), raw_state_by_route_key, fn route_key, acc ->
      if disabled_route?(policy_by_route_key, route_key) do
        Map.delete(acc, route_key)
      else
        acc
      end
    end)
  end

  def remove_disabled_raw_states(raw_state_by_route_key, _policy_by_route_key, _profile_module),
    do: raw_state_by_route_key

  defp normalize_effective_raw_state_by_route_key(raw_state_by_route_key, profile_module) when is_map(raw_state_by_route_key) do
    Enum.reduce(identity_raw_state_by_route_key(profile_module), identity_raw_state_by_route_key(profile_module), fn {route_key, default_state}, acc ->
      Map.put(acc, route_key, raw_state_for_route_key(raw_state_by_route_key, route_key) || default_state)
    end)
  end

  defp normalize_effective_raw_state_by_route_key(_raw_state_by_route_key, profile_module),
    do: identity_raw_state_by_route_key(profile_module)

  defp merge_raw_config_state_by_route_key(base_raw_state_by_route_key, raw_state_by_route_key, profile_module)
       when is_map(raw_state_by_route_key) do
    Enum.reduce(route_keys(profile_module), base_raw_state_by_route_key, fn route_key, acc ->
      case raw_config_raw_state_for_route_key(raw_state_by_route_key, route_key) do
        nil -> acc
        raw_state -> Map.put(acc, route_key, raw_state)
      end
    end)
  end

  defp merge_raw_config_state_by_route_key(base_raw_state_by_route_key, _raw_state_by_route_key, _profile_module),
    do: base_raw_state_by_route_key

  defp overlay_effective_raw_state_by_route_key(base_raw_state_by_route_key, raw_state_by_route_key, profile_module)
       when is_map(raw_state_by_route_key) do
    Enum.reduce(route_keys(profile_module), base_raw_state_by_route_key, fn route_key, acc ->
      case raw_state_for_route_key(raw_state_by_route_key, route_key) do
        nil -> acc
        raw_state -> Map.put(acc, route_key, raw_state)
      end
    end)
  end

  defp overlay_effective_raw_state_by_route_key(base_raw_state_by_route_key, _raw_state_by_route_key, _profile_module),
    do: base_raw_state_by_route_key

  defp raw_config_raw_state_for_route_key(raw_state_by_route_key, route_key)
       when is_map(raw_state_by_route_key) and is_atom(route_key) do
    raw_state_by_route_key
    |> raw_config_route_entry_for_route_key(route_key)
    |> normalize_raw_state()
  end

  defp raw_config_raw_state_for_route_key(_raw_state_by_route_key, _route_key), do: nil

  defp raw_config_route_entry_for_route_key(raw_state_by_route_key, route_key)
       when is_map(raw_state_by_route_key) and is_atom(route_key) do
    Map.get(raw_state_by_route_key, Atom.to_string(route_key))
  end

  defp normalize_raw_state(raw_state) when is_binary(raw_state) do
    case String.trim(raw_state) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_raw_state(_raw_state), do: nil

  defp normalize_policy_by_route_key(policy_by_route_key, profile_module) when is_map(policy_by_route_key) do
    default_policy_by_route_key = default_policy_by_route_key(profile_module)

    Enum.reduce(default_policy_by_route_key, default_policy_by_route_key, fn {route_key, default_policy}, acc ->
      normalized_policy =
        policy_by_route_key
        |> effective_policy_entry_for_route_key(route_key)
        |> normalize_effective_policy_entry(default_policy)

      Map.put(acc, route_key, normalized_policy)
    end)
  end

  defp normalize_policy_by_route_key(_policy_by_route_key, profile_module), do: default_policy_by_route_key(profile_module)

  defp merge_policy_by_route_key(base_policy_by_route_key, policy_by_route_key, profile_module)
       when is_map(policy_by_route_key) do
    Enum.reduce(default_policy_by_route_key(profile_module), base_policy_by_route_key, fn {route_key, _default_policy}, acc ->
      case raw_policy_entry_for_route_key(policy_by_route_key, route_key) do
        policy when is_map(policy) ->
          Map.put(acc, route_key, normalize_raw_policy_entry(policy, Map.get(acc, route_key, %{}), profile_module))

        _ ->
          acc
      end
    end)
  end

  defp merge_policy_by_route_key(base_policy_by_route_key, _policy_by_route_key, _profile_module),
    do: base_policy_by_route_key

  defp overlay_effective_policy_by_route_key(base_policy_by_route_key, policy_by_route_key, profile_module)
       when is_map(base_policy_by_route_key) and is_map(policy_by_route_key) do
    Enum.reduce(default_policy_by_route_key(profile_module), base_policy_by_route_key, fn {route_key, _default_policy}, acc ->
      case effective_policy_entry_for_route_key(policy_by_route_key, route_key) do
        policy when is_map(policy) and map_size(policy) > 0 -> Map.put(acc, route_key, policy)
        _policy -> acc
      end
    end)
  end

  defp overlay_effective_policy_by_route_key(base_policy_by_route_key, _policy_by_route_key, _profile_module),
    do: base_policy_by_route_key

  defp effective_policy_entry_for_route_key(policy_by_route_key, route_key)
       when is_map(policy_by_route_key) and is_atom(route_key) do
    Map.get(policy_by_route_key, route_key)
  end

  defp effective_policy_entry_for_route_key(_policy_by_route_key, _route_key), do: nil

  defp raw_policy_entry_for_route_key(policy_by_route_key, route_key)
       when is_map(policy_by_route_key) and is_atom(route_key) do
    Map.get(policy_by_route_key, Atom.to_string(route_key))
  end

  defp raw_policy_entry_for_route_key(_policy_by_route_key, _route_key), do: nil

  defp normalize_effective_policy_entry(entry, base_policy) when is_map(entry) and is_map(base_policy) do
    action =
      if Map.has_key?(entry, :action) do
        Map.get(entry, :action)
      else
        Map.get(base_policy, :action)
      end

    transition_target =
      if transition_action?(action) do
        if Map.has_key?(entry, :transition_target) do
          Map.get(entry, :transition_target)
        else
          if transition_action?(Map.get(base_policy, :action)) do
            Map.get(base_policy, :transition_target)
          end
        end
      end

    execution_profile =
      if action == :dispatch do
        if Map.has_key?(entry, :execution_profile) do
          Map.get(entry, :execution_profile)
        else
          if Map.get(base_policy, :action) == :dispatch do
            Map.get(base_policy, :execution_profile)
          end
        end
      end

    %{action: action}
    |> maybe_put(:transition_target, transition_target)
    |> maybe_put(:execution_profile, execution_profile)
  end

  defp normalize_effective_policy_entry(_entry, base_policy) when is_map(base_policy), do: base_policy

  defp normalize_raw_policy_entry(entry, base_policy, profile_module) when is_map(entry) and is_map(base_policy) do
    action =
      if raw_entry_has_key?(entry, :action) do
        entry
        |> raw_entry_field(:action)
        |> normalize_action()
      else
        Map.get(base_policy, :action)
      end

    transition_target =
      if transition_action?(action) do
        if raw_entry_has_key?(entry, :transition_target) do
          entry
          |> raw_entry_field(:transition_target)
          |> normalize_route_key(profile_module)
        else
          if transition_action?(Map.get(base_policy, :action)) do
            Map.get(base_policy, :transition_target)
          end
        end
      end

    execution_profile =
      if action == :dispatch do
        if raw_entry_has_key?(entry, :execution_profile) do
          entry
          |> raw_entry_field(:execution_profile)
          |> normalize_name()
        else
          if Map.get(base_policy, :action) == :dispatch do
            Map.get(base_policy, :execution_profile)
          end
        end
      end

    %{action: action}
    |> maybe_put(:transition_target, transition_target)
    |> maybe_put(:execution_profile, execution_profile)
  end

  defp normalize_raw_policy_entry(_entry, base_policy, _profile_module) when is_map(base_policy), do: base_policy

  defp raw_entry_field(entry, key) when is_map(entry) and is_atom(key) do
    Map.get(entry, Atom.to_string(key))
  end

  defp raw_entry_field(_entry, _key), do: nil

  defp raw_entry_has_key?(entry, key) when is_map(entry) and is_atom(key) do
    Map.has_key?(entry, Atom.to_string(key))
  end

  defp raw_entry_has_key?(_entry, _key), do: false

  defp normalize_name(nil), do: nil

  defp normalize_name(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_name()
  end

  defp normalize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      trimmed ->
        trimmed
        |> String.downcase()
        |> String.replace(~r/[\s-]+/, "_")
    end
  end

  defp normalize_name(_value), do: nil

  defp maybe_put(map, _key, nil), do: map

  defp maybe_put(map, key, value) do
    Map.put(map, key, value)
  end
end
