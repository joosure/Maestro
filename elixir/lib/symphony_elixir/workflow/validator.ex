defmodule SymphonyElixir.Workflow.Validator do
  @moduledoc """
  Tracker-agnostic validation for resolved workflow profile route maps.

  Trackers may still own vendor-specific config validation, but profile route
  vocabulary, raw-state route maps, route-policy entries, transition targets,
  execution-profile admission, and lifecycle phase expectations are shared
  Workflow Core concerns.
  """

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RoutePolicy.Validator, as: RoutePolicyValidator

  @type scope :: :global | String.t()

  @spec validate_workflow(scope(), map()) :: :ok | {:error, term()}
  def validate_workflow(scope, workflow) when is_map(workflow) do
    with {:ok, profile_context} <- profile_context_for_workflow(workflow),
         :ok <-
           validate_raw_state_by_route_key_entries(
             scope,
             Map.get(workflow, :raw_state_by_route_key, %{}),
             profile_context.module
           ),
         :ok <- validate_raw_state_membership(scope, workflow, profile_context),
         :ok <- validate_raw_state_lifecycle_phases(scope, workflow, profile_context),
         :ok <- validate_policy_by_route_key(scope, workflow, profile_context) do
      :ok
    end
  end

  def validate_workflow(scope, workflow), do: {:error, {:invalid_workflow_entry, scope, workflow}}

  @spec validate_raw_state_by_route_key_entries(scope(), map() | term(), module()) ::
          :ok | {:error, term()}
  def validate_raw_state_by_route_key_entries(scope, raw_state_by_route_key, profile_module)
      when is_map(raw_state_by_route_key) and is_atom(profile_module) do
    Enum.reduce_while(raw_state_by_route_key, :ok, fn {route_key, raw_tracker_state}, :ok ->
      case RoutePolicy.normalize_route_key(route_key, profile_module) do
        nil ->
          {:halt, {:error, {:invalid_raw_state_route_key, scope, route_key}}}

        normalized_route_key ->
          case normalize_string(raw_tracker_state) do
            nil ->
              {:halt, {:error, {:invalid_raw_state_by_route_key_value, scope, normalized_route_key, raw_tracker_state}}}

            _raw_state ->
              {:cont, :ok}
          end
      end
    end)
  end

  def validate_raw_state_by_route_key_entries(_scope, _raw_state_by_route_key, _profile_module), do: :ok

  @spec validate_policy_by_route_key_entries(scope(), map() | term(), ProfileRegistry.resolved_profile()) ::
          :ok | {:error, term()}
  def validate_policy_by_route_key_entries(scope, policy_by_route_key, profile_context) do
    RoutePolicyValidator.validate_entries(scope, policy_by_route_key, profile_context)
  end

  @spec validate_policy_by_route_key(scope(), map(), ProfileRegistry.resolved_profile()) ::
          :ok | {:error, term()}
  def validate_policy_by_route_key(scope, workflow, profile_context) do
    RoutePolicyValidator.validate_effective_policy(scope, workflow, profile_context)
  end

  defp validate_raw_state_membership(scope, workflow, %{module: profile_module}) do
    raw_state_by_route_key = Map.get(workflow, :raw_state_by_route_key, %{})
    active_states = Map.get(workflow, :active_states, [])
    terminal_states = Map.get(workflow, :terminal_states, [])
    policy_by_route_key = Map.get(workflow, :policy_by_route_key, %{})
    expected_phase_by_route = RoutePolicy.expected_lifecycle_phases(profile_module)

    Enum.reduce_while(RoutePolicy.route_keys(profile_module), :ok, fn route_key, :ok ->
      raw_state = RoutePolicy.raw_state_for_route_key(raw_state_by_route_key, route_key)
      expected_phase = Map.get(expected_phase_by_route, route_key)
      policy = route_policy_entry(policy_by_route_key, route_key)
      action = RoutePolicy.normalize_action(Map.get(policy, :action))

      cond do
        expected_phase in ["done", "canceled"] ->
          if raw_state in terminal_states do
            {:cont, :ok}
          else
            {:halt, {:error, {:raw_state_not_terminal, scope, route_key, raw_state}}}
          end

        action in [:dispatch, :transition, :transition_then_dispatch] ->
          if raw_state in active_states do
            {:cont, :ok}
          else
            {:halt, {:error, {:raw_state_not_active, scope, route_key, raw_state}}}
          end

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_raw_state_lifecycle_phases(scope, workflow, %{module: profile_module}) do
    raw_state_by_route_key = Map.get(workflow, :raw_state_by_route_key, %{})
    state_phase_map = Map.get(workflow, :state_phase_map, %{})
    expected_phase_by_route = RoutePolicy.expected_lifecycle_phases(profile_module)

    Enum.reduce_while(expected_phase_by_route, :ok, fn {route_key, expected_phase}, :ok ->
      raw_state = RoutePolicy.raw_state_for_route_key(raw_state_by_route_key, route_key)
      actual_phase = WorkflowLifecycle.phase_for_state(raw_state, state_phase_map)

      cond do
        is_nil(raw_state) ->
          {:halt, {:error, {:missing_raw_state_for_route_key, scope, route_key}}}

        actual_phase == expected_phase ->
          {:cont, :ok}

        true ->
          {:halt, {:error, {:invalid_raw_state_lifecycle_phase, scope, route_key, raw_state, actual_phase, expected_phase}}}
      end
    end)
  end

  defp profile_context_for_workflow(workflow) when is_map(workflow) do
    workflow
    |> Map.get(:profile, %{})
    |> ProfileRegistry.resolve()
    |> case do
      {:ok, resolved_profile} -> {:ok, resolved_profile}
      {:error, reason} -> {:error, {:invalid_workflow_profile, reason}}
    end
  end

  defp route_policy_entry(policy_by_route_key, route_key)
       when is_map(policy_by_route_key) and is_atom(route_key) do
    Map.get(policy_by_route_key, route_key) ||
      Map.get(policy_by_route_key, Atom.to_string(route_key)) ||
      %{}
  end

  defp route_policy_entry(_policy_by_route_key, _route_key), do: %{}

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(_value), do: nil
end
