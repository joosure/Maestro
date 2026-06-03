defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry.Selection do
  @moduledoc false

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Resolver
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Values
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy

  @type resolved_profile :: ProfileRegistry.resolved_profile()
  @type selected_execution_profile :: %{
          scope: :global | String.t(),
          route_key: atom(),
          action: atom(),
          execution_profile: String.t()
        }

  @spec selected_execution_profiles(map(), resolved_profile()) :: [selected_execution_profile()]
  def selected_execution_profiles(settings, %{module: profile_module, options: profile_options}) when is_map(settings) do
    settings
    |> effective_policy_by_route_key_sets(profile_module, profile_options)
    |> Enum.flat_map(&execution_profiles_from_policy_by_route_key/1)
  end

  @spec validate_selected_execution_profiles(map(), resolved_profile()) :: :ok | {:error, term()}
  def validate_selected_execution_profiles(settings, profile_context) when is_map(settings) do
    with :ok <- validate_raw_execution_profile_usage(settings, profile_context) do
      settings
      |> selected_execution_profiles(profile_context)
      |> Enum.reduce_while(:ok, fn %{execution_profile: execution_profile, action: action} = selected, :ok ->
        case Resolver.resolve(profile_context, execution_profile, action) do
          {:ok, _resolved} ->
            {:cont, :ok}

          {:error, reason} ->
            {:halt, {:error, {:invalid_selected_workflow_execution_profile, selected, reason}}}
        end
      end)
    end
  end

  defp effective_policy_by_route_key_sets(settings, profile_module, profile_options) do
    lifecycle =
      settings
      |> Values.map_field(:tracker)
      |> Values.map_field(:lifecycle)

    default_policy_by_route_key = ProfileRegistry.default_policy_by_route_key(profile_module, profile_options)

    global_policy_by_route_key =
      lifecycle
      |> Values.map_field(:policy_by_route_key)
      |> RoutePolicy.resolve_policy_by_route_key(default_policy_by_route_key, profile_module)

    workflows_by_type = lifecycle |> Values.map_field(:workflows_by_type) |> Values.normalize_map()

    if map_size(workflows_by_type) == 0 do
      [{:global, global_policy_by_route_key}]
    else
      Enum.map(workflows_by_type, fn {workitem_type_id, workflow} ->
        policy_by_route_key =
          workflow
          |> Values.map_field(:policy_by_route_key)
          |> RoutePolicy.resolve_policy_by_route_key(global_policy_by_route_key, profile_module)

        {to_string(workitem_type_id), policy_by_route_key}
      end)
    end
  end

  defp execution_profiles_from_policy_by_route_key({scope, policy_by_route_key}) when is_map(policy_by_route_key) do
    Enum.flat_map(policy_by_route_key, fn
      {route_key, %{action: action, execution_profile: execution_profile}}
      when is_atom(route_key) and is_atom(action) and is_binary(execution_profile) ->
        [
          %{
            scope: scope,
            route_key: route_key,
            action: action,
            execution_profile: execution_profile
          }
        ]

      _policy ->
        []
    end)
  end

  defp execution_profiles_from_policy_by_route_key(_policy_by_route_key), do: []

  defp validate_raw_execution_profile_usage(settings, %{module: profile_module, options: profile_options}) do
    lifecycle =
      settings
      |> Values.map_field(:tracker)
      |> Values.map_field(:lifecycle)

    default_policy_by_route_key = ProfileRegistry.default_policy_by_route_key(profile_module, profile_options)
    global_policy_overrides = lifecycle |> Values.map_field(:policy_by_route_key) |> Values.normalize_map()

    with :ok <-
           validate_raw_policy_execution_profile_usage(
             :global,
             global_policy_overrides,
             default_policy_by_route_key,
             profile_module
           ) do
      global_policy_by_route_key =
        RoutePolicy.resolve_policy_by_route_key(global_policy_overrides, default_policy_by_route_key, profile_module)

      lifecycle
      |> Values.map_field(:workflows_by_type)
      |> Values.normalize_map()
      |> Enum.reduce_while(:ok, fn {workitem_type_id, workflow}, :ok ->
        policy_overrides = workflow |> Values.map_field(:policy_by_route_key) |> Values.normalize_map()

        case validate_raw_policy_execution_profile_usage(
               to_string(workitem_type_id),
               policy_overrides,
               global_policy_by_route_key,
               profile_module
             ) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp validate_raw_policy_execution_profile_usage(scope, policy_overrides, base_policy_by_route_key, profile_module)
       when is_map(policy_overrides) and is_map(base_policy_by_route_key) do
    Enum.reduce_while(policy_overrides, :ok, fn {route_key, policy}, :ok ->
      normalized_route_key = RoutePolicy.normalize_route_key(route_key, profile_module)

      cond do
        is_nil(normalized_route_key) ->
          {:cont, :ok}

        not is_map(policy) or not route_policy_entry_has_key?(policy, :execution_profile) ->
          {:cont, :ok}

        true ->
          base_policy = effective_route_policy(base_policy_by_route_key, normalized_route_key)

          case validate_raw_policy_execution_profile_entry(scope, normalized_route_key, policy, base_policy) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp validate_raw_policy_execution_profile_entry(scope, route_key, policy, base_policy) do
    action =
      if route_policy_entry_has_key?(policy, :action) do
        policy
        |> route_policy_entry_field(:action)
        |> RoutePolicy.normalize_action()
      else
        Map.get(base_policy, :action)
      end

    execution_profile = route_policy_entry_field(policy, :execution_profile)

    cond do
      action != :dispatch ->
        {:error, {:invalid_workflow_execution_profile_usage, scope, route_key, :unsupported_action, action}}

      is_nil(Values.normalize_name(execution_profile)) ->
        {:error, {:invalid_workflow_execution_profile_usage, scope, route_key, :invalid_name, execution_profile}}

      true ->
        :ok
    end
  end

  defp effective_route_policy(policy_by_route_key, route_key)
       when is_map(policy_by_route_key) and is_atom(route_key) do
    RoutePolicy.policy_for_route_key(policy_by_route_key, route_key)
  end

  defp effective_route_policy(_policy_by_route_key, _route_key), do: %{}

  defp route_policy_entry_field(entry, key) when is_map(entry) and is_atom(key) do
    Map.get(entry, Atom.to_string(key))
  end

  defp route_policy_entry_has_key?(entry, key) when is_map(entry) and is_atom(key) do
    Map.has_key?(entry, Atom.to_string(key))
  end

  defp route_policy_entry_has_key?(_entry, _key), do: false
end
