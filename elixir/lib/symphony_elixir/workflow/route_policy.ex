defmodule SymphonyElixir.Workflow.RoutePolicy do
  @moduledoc """
  Route-policy helpers for workflow-profile route actions.

  Route keys are Symphony workflow-profile vocabulary. Raw tracker states live in
  `raw_state_by_route_key`, and lifecycle phases live in `state_phase_map`.
  """

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy.Keys

  @actions MapSet.new([:dispatch, :wait, :stop, :transition, :transition_then_dispatch])
  @transition_actions MapSet.new([:transition, :transition_then_dispatch])

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

  @spec route_key?(term(), module()) :: boolean()
  def route_key?(route_key, profile_module \\ ProfileRegistry.default_profile_module()),
    do: Keys.route_key?(route_key, profile_module)

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
  def valid_action?(action) do
    action
    |> normalize_action()
    |> then(&MapSet.member?(@actions, &1))
  end

  @spec transition_action?(term()) :: boolean()
  def transition_action?(action) do
    action
    |> normalize_action()
    |> then(&MapSet.member?(@transition_actions, &1))
  end

  @spec normalize_action(term()) :: atom() | nil
  def normalize_action(action_name) when is_atom(action_name) do
    action_name
    |> Atom.to_string()
    |> normalize_action()
  end

  def normalize_action(action_name) when is_binary(action_name) do
    case normalize_name(action_name) do
      "dispatch" -> :dispatch
      "wait" -> :wait
      "stop" -> :stop
      "transition" -> :transition
      "transition_then_dispatch" -> :transition_then_dispatch
      _ -> nil
    end
  end

  def normalize_action(_action_name), do: nil

  @spec normalize_route_key(term(), module()) :: atom() | nil
  def normalize_route_key(route_key, profile_module \\ ProfileRegistry.default_profile_module())

  def normalize_route_key(route_key, profile_module), do: Keys.normalize_route_key(route_key, profile_module)

  @spec raw_state_for_route_key(map(), atom()) :: String.t() | nil
  def raw_state_for_route_key(raw_state_by_route_key, route_key) when is_map(raw_state_by_route_key) and is_atom(route_key) do
    value = Map.get(raw_state_by_route_key, route_key) || Map.get(raw_state_by_route_key, Atom.to_string(route_key))

    case value do
      raw_state when is_binary(raw_state) ->
        case String.trim(raw_state) do
          "" -> nil
          normalized -> normalized
        end

      _ ->
        nil
    end
  end

  def raw_state_for_route_key(_raw_state_by_route_key, _route_key), do: nil

  defp normalize_policy_by_route_key(policy_by_route_key, profile_module) when is_map(policy_by_route_key) do
    default_policy_by_route_key = default_policy_by_route_key(profile_module)

    Enum.reduce(default_policy_by_route_key, default_policy_by_route_key, fn {route_key, default_policy}, acc ->
      normalized_policy =
        policy_by_route_key
        |> policy_entry(route_key)
        |> normalize_policy_entry(default_policy, profile_module)

      Map.put(acc, route_key, normalized_policy)
    end)
  end

  defp normalize_policy_by_route_key(_policy_by_route_key, profile_module), do: default_policy_by_route_key(profile_module)

  defp merge_policy_by_route_key(base_policy_by_route_key, policy_by_route_key, profile_module)
       when is_map(policy_by_route_key) do
    Enum.reduce(default_policy_by_route_key(profile_module), base_policy_by_route_key, fn {route_key, _default_policy}, acc ->
      case policy_entry(policy_by_route_key, route_key) do
        policy when is_map(policy) ->
          Map.put(acc, route_key, normalize_policy_entry(policy, Map.get(acc, route_key, %{}), profile_module))

        _ ->
          acc
      end
    end)
  end

  defp merge_policy_by_route_key(base_policy_by_route_key, _policy_by_route_key, _profile_module),
    do: base_policy_by_route_key

  defp policy_entry(policy_by_route_key, route_key) when is_map(policy_by_route_key) and is_atom(route_key) do
    Map.get(policy_by_route_key, route_key) || Map.get(policy_by_route_key, Atom.to_string(route_key))
  end

  defp policy_entry(_policy_by_route_key, _route_key), do: nil

  defp normalize_policy_entry(entry, base_policy, profile_module) when is_map(entry) and is_map(base_policy) do
    action =
      if entry_has_key?(entry, :action) do
        entry
        |> entry_field(:action)
        |> normalize_action()
      else
        Map.get(base_policy, :action)
      end

    transition_target =
      if transition_action?(action) do
        if entry_has_key?(entry, :transition_target) do
          entry
          |> entry_field(:transition_target)
          |> normalize_route_key(profile_module)
        else
          if transition_action?(Map.get(base_policy, :action)) do
            Map.get(base_policy, :transition_target)
          end
        end
      end

    execution_profile =
      if action == :dispatch do
        if entry_has_key?(entry, :execution_profile) do
          entry
          |> entry_field(:execution_profile)
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

  defp normalize_policy_entry(_entry, base_policy, _profile_module) when is_map(base_policy), do: base_policy

  defp entry_field(entry, key) when is_map(entry) and is_atom(key) do
    Map.get(entry, key) || Map.get(entry, Atom.to_string(key))
  end

  defp entry_field(_entry, _key), do: nil

  defp entry_has_key?(entry, key) when is_map(entry) and is_atom(key) do
    Map.has_key?(entry, key) || Map.has_key?(entry, Atom.to_string(key))
  end

  defp entry_has_key?(_entry, _key), do: false

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
