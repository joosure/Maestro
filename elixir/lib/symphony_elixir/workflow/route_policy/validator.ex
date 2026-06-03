defmodule SymphonyElixir.Workflow.RoutePolicy.Validator do
  @moduledoc """
  Tracker-agnostic validation for workflow route-policy maps.
  """

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef

  @type scope :: :global | String.t()

  @route_policy_entry_fields MapSet.new(["action", "transition_target", "execution_profile"])
  @effective_route_policy_entry_fields MapSet.new([:action, :transition_target, :execution_profile])

  @spec validate_entries(scope(), map() | term(), ProfileRegistry.resolved_profile()) ::
          :ok | {:error, term()}
  def validate_entries(scope, policy_by_route_key, %{module: profile_module} = profile_context)
      when is_map(policy_by_route_key) do
    Enum.reduce_while(policy_by_route_key, :ok, fn {route_policy_key, policy}, :ok ->
      case raw_config_route_key(route_policy_key, profile_module) do
        nil ->
          {:halt, {:error, {:invalid_route_policy_key, scope, invalid_raw_config_route_key_reason(profile_context, route_policy_key)}}}

        route_key ->
          case validate_route_policy_entry_config(scope, route_key, policy, profile_context) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  def validate_entries(_scope, _policy_by_route_key, _profile_context), do: :ok

  @spec validate_effective_policy(scope(), map(), ProfileRegistry.resolved_profile()) ::
          :ok | {:error, term()}
  def validate_effective_policy(scope, workflow, %{module: profile_module} = profile_context)
      when is_map(workflow) do
    policy_by_route_key = Map.get(workflow, :policy_by_route_key, %{})
    raw_state_by_route_key = Map.get(workflow, :raw_state_by_route_key, %{})
    state_phase_map = Map.get(workflow, :state_phase_map, %{})

    with :ok <- validate_effective_entries(scope, policy_by_route_key, profile_context) do
      Enum.reduce_while(RoutePolicy.route_keys(profile_module), :ok, fn route_key, :ok ->
        policy = RoutePolicy.policy_for_route_key(policy_by_route_key, route_key)

        with :ok <- validate_route_policy_action(scope, route_key, policy, profile_context),
             :ok <- validate_route_policy_execution_profile(scope, route_key, policy, profile_context),
             :ok <-
               validate_route_policy_transition_target(
                 scope,
                 route_key,
                 policy,
                 raw_state_by_route_key,
                 state_phase_map,
                 profile_context
               ) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp validate_effective_entries(scope, policy_by_route_key, %{module: profile_module} = profile_context)
       when is_map(policy_by_route_key) do
    Enum.reduce_while(policy_by_route_key, :ok, fn {route_policy_key, policy}, :ok ->
      cond do
        not is_atom(route_policy_key) or not RoutePolicy.route_key?(route_policy_key, profile_module) ->
          {:halt, {:error, {:invalid_route_policy_key, scope, invalid_effective_route_key_reason(profile_context, route_policy_key)}}}

        not is_map(policy) ->
          {:halt, {:error, {:invalid_route_policy_entry, scope, route_ref(profile_context, route_policy_key), policy}}}

        true ->
          case validate_effective_route_policy_entry_fields(scope, route_policy_key, policy, profile_context) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp validate_effective_entries(_scope, _policy_by_route_key, _profile_context), do: :ok

  defp validate_effective_route_policy_entry_fields(scope, route_key, policy, profile_context) when is_map(policy) do
    Enum.reduce_while(policy, :ok, fn {field, _value}, :ok ->
      if MapSet.member?(@effective_route_policy_entry_fields, field) do
        {:cont, :ok}
      else
        {:halt, {:error, {:unsupported_route_policy_field, scope, route_ref(profile_context, route_key), field}}}
      end
    end)
  end

  defp validate_route_policy_entry_config(
         scope,
         route_key,
         policy,
         %{module: profile_module, options: profile_options} = profile_context
       )
       when is_map(policy) do
    default_policy =
      profile_module
      |> ProfileRegistry.default_policy_by_route_key(profile_options)
      |> RoutePolicy.policy_for_route_key(route_key)

    with :ok <- validate_route_policy_entry_fields(scope, route_key, policy, profile_context),
         :ok <-
           validate_route_policy_entry_transition_target_config(
             scope,
             route_key,
             policy,
             default_policy,
             profile_context
           ),
         :ok <-
           validate_route_policy_entry_execution_profile_config(
             scope,
             route_key,
             policy,
             default_policy,
             profile_context
           ) do
      :ok
    end
  end

  defp validate_route_policy_entry_config(scope, route_key, policy, profile_context) do
    {:error, {:invalid_route_policy_entry, scope, route_ref(profile_context, route_key), policy}}
  end

  defp validate_route_policy_entry_fields(scope, route_key, policy, profile_context) when is_map(policy) do
    Enum.reduce_while(policy, :ok, fn {field, _value}, :ok ->
      if is_binary(field) and MapSet.member?(@route_policy_entry_fields, field) do
        {:cont, :ok}
      else
        {:halt, {:error, {:unsupported_route_policy_field, scope, route_ref(profile_context, route_key), field}}}
      end
    end)
  end

  defp validate_route_policy_entry_transition_target_config(
         scope,
         route_key,
         policy,
         default_policy,
         %{module: profile_module} = profile_context
       )
       when is_map(policy) and is_map(default_policy) do
    if route_policy_entry_has_key?(policy, :transition_target) do
      action =
        if route_policy_entry_has_key?(policy, :action) do
          policy
          |> route_policy_entry_field(:action)
          |> RoutePolicy.normalize_action()
        else
          Map.get(default_policy, :action)
        end

      transition_target = route_policy_entry_field(policy, :transition_target)

      cond do
        not RoutePolicy.transition_action?(action) ->
          {:error, {:invalid_route_policy_transition_target_action, scope, route_ref(profile_context, route_key), action}}

        RoutePolicy.route_key?(transition_target, profile_module) ->
          :ok

        true ->
          {:error, {:invalid_route_policy_transition_target_key, scope, route_ref(profile_context, route_key), invalid_route_key_reason(profile_context, transition_target)}}
      end
    else
      :ok
    end
  end

  defp validate_route_policy_entry_execution_profile_config(
         scope,
         route_key,
         policy,
         default_policy,
         profile_context
       )
       when is_map(policy) and is_map(default_policy) do
    if route_policy_entry_has_key?(policy, :execution_profile) do
      action =
        if route_policy_entry_has_key?(policy, :action) do
          policy
          |> route_policy_entry_field(:action)
          |> RoutePolicy.normalize_action()
        else
          Map.get(default_policy, :action)
        end

      execution_profile = route_policy_entry_field(policy, :execution_profile)

      cond do
        action != :dispatch ->
          {:error, {:invalid_route_policy_execution_profile_action, scope, route_ref(profile_context, route_key), action}}

        is_nil(ExecutionProfileRegistry.normalize_name(execution_profile)) ->
          {:error, {:invalid_route_policy_execution_profile, scope, route_ref(profile_context, route_key), execution_profile}}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp validate_route_policy_action(scope, route_key, policy, profile_context) when is_map(policy) do
    action = Map.get(policy, :action)

    if RoutePolicy.valid_action?(action) do
      :ok
    else
      {:error, {:invalid_route_policy_action, scope, route_ref(profile_context, route_key), action}}
    end
  end

  defp validate_route_policy_execution_profile(
         scope,
         route_key,
         policy,
         profile_context
       )
       when is_map(policy) do
    execution_profile = Map.get(policy, :execution_profile)
    action = Map.get(policy, :action)

    cond do
      is_nil(execution_profile) ->
        :ok

      action != :dispatch ->
        {:error, {:invalid_route_policy_execution_profile_action, scope, route_ref(profile_context, route_key), action}}

      true ->
        case ExecutionProfileRegistry.resolve(profile_context, execution_profile, action) do
          {:ok, _resolved_execution_profile} ->
            :ok

          {:error, {:unsupported_workflow_execution_profile_action, _execution_profile, _action}} ->
            {:error, {:invalid_route_policy_execution_profile_action, scope, route_ref(profile_context, route_key), action}}

          {:error, _reason} ->
            {:error, {:unsupported_route_policy_execution_profile, scope, route_ref(profile_context, route_key), execution_profile}}
        end
    end
  end

  defp validate_route_policy_transition_target(
         scope,
         route_key,
         policy,
         raw_state_by_route_key,
         state_phase_map,
         profile_context
       )
       when is_map(policy) and is_map(raw_state_by_route_key) and is_map(state_phase_map) do
    action = Map.get(policy, :action)
    transition_target = Map.get(policy, :transition_target)

    cond do
      not is_nil(transition_target) and not RoutePolicy.transition_action?(action) ->
        {:error, {:invalid_route_policy_transition_target_action, scope, route_ref(profile_context, route_key), action}}

      not RoutePolicy.transition_action?(action) ->
        :ok

      is_nil(transition_target) ->
        {:error, {:missing_route_policy_transition_target, scope, route_ref(profile_context, route_key)}}

      not is_atom(transition_target) ->
        {:error, {:invalid_route_policy_transition_target_key, scope, route_ref(profile_context, route_key), invalid_effective_route_key_reason(profile_context, transition_target)}}

      transition_target == route_key ->
        {:error, {:route_policy_transition_target_cycle, scope, route_ref(profile_context, route_key), route_ref(profile_context, transition_target)}}

      true ->
        target_state = RoutePolicy.raw_state_for_route_key(raw_state_by_route_key, transition_target)
        target_phase = WorkflowLifecycle.phase_for_state(target_state, state_phase_map)

        cond do
          is_nil(target_state) ->
            {:error, {:invalid_route_policy_transition_target, scope, route_ref(profile_context, route_key), route_ref(profile_context, transition_target)}}

          action == :transition_then_dispatch and not WorkflowLifecycle.dispatch_blocker_phase?(target_phase) ->
            {:error, {:invalid_route_policy_transition_phase, scope, route_ref(profile_context, route_key), route_ref(profile_context, transition_target), target_phase}}

          true ->
            :ok
        end
    end
  end

  defp validate_route_policy_transition_target(
         scope,
         route_key,
         policy,
         _raw_state_by_route_key,
         _state_phase_map,
         profile_context
       ) do
    {:error, {:invalid_route_policy_action, scope, route_ref(profile_context, route_key), policy}}
  end

  defp route_ref(profile_context, route_key), do: RouteRef.new!(profile_context, route_key)

  defp invalid_route_key_reason(profile_context, route_key) do
    case RouteRef.new(profile_context, route_key) do
      {:ok, route_ref} -> route_ref
      {:error, reason} -> reason
    end
  end

  defp invalid_effective_route_key_reason(profile_context, route_key) do
    {:invalid_workflow_route_key, profile_context.kind, profile_context.version, route_key}
  end

  defp invalid_raw_config_route_key_reason(profile_context, route_key) when is_binary(route_key) do
    invalid_route_key_reason(profile_context, route_key)
  end

  defp invalid_raw_config_route_key_reason(profile_context, route_key) do
    {:invalid_workflow_route_key, profile_context.kind, profile_context.version, route_key}
  end

  defp raw_config_route_key(route_key, profile_module) when is_binary(route_key) do
    RoutePolicy.normalize_route_key(route_key, profile_module)
  end

  defp raw_config_route_key(_route_key, _profile_module), do: nil

  defp route_policy_entry_field(entry, key) when is_map(entry) and is_atom(key) do
    Map.get(entry, Atom.to_string(key))
  end

  defp route_policy_entry_has_key?(entry, key) when is_map(entry) and is_atom(key) do
    Map.has_key?(entry, Atom.to_string(key))
  end

  defp route_policy_entry_has_key?(_entry, _key), do: false
end
