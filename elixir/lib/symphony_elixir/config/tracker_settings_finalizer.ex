defmodule SymphonyElixir.Config.TrackerSettingsFinalizer do
  @moduledoc false

  alias SymphonyElixir.Config.InputNormalizer
  alias SymphonyElixir.Tracker, as: TrackerAdapter
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @spec finalize(struct(), struct() | nil) :: struct()
  def finalize(tracker, workflow \\ nil) do
    defaults = TrackerAdapter.defaults(tracker.kind)
    default_auth = normalize_default_map(defaults[:auth])
    default_provider = normalize_default_map(defaults[:provider])
    default_lifecycle = normalize_default_map(defaults[:lifecycle])
    env_vars = normalize_default_map(defaults[:env_vars])

    auth =
      default_auth
      |> merge_section(tracker.auth)
      |> finalize_section(Map.get(env_vars, "auth"))
      |> normalize_secret_values()

    provider =
      default_provider
      |> merge_section(tracker.provider)
      |> finalize_section(Map.get(env_vars, "provider"))

    lifecycle = merge_section(default_lifecycle, tracker.lifecycle)
    workflow_profile = workflow_profile(workflow)
    endpoint = tracker.endpoint || defaults[:endpoint]

    active_states =
      lifecycle
      |> Map.get("active_states")
      |> default_if_empty(Map.get(default_lifecycle, "active_states"))
      |> List.wrap()

    terminal_states =
      lifecycle
      |> Map.get("terminal_states")
      |> default_if_empty(Map.get(default_lifecycle, "terminal_states"))
      |> List.wrap()

    state_phase_map =
      lifecycle
      |> Map.get("state_phase_map")
      |> default_if_empty(Map.get(default_lifecycle, "state_phase_map"))
      |> WorkflowLifecycle.normalize_state_phase_map()

    raw_state_by_route_key =
      lifecycle
      |> Map.get("raw_state_by_route_key")
      |> InputNormalizer.normalize_optional_map()

    policy_by_route_key =
      lifecycle
      |> Map.get("policy_by_route_key")
      |> InputNormalizer.normalize_optional_map()

    workflows_by_type =
      lifecycle
      |> Map.get("workflows_by_type")
      |> InputNormalizer.normalize_optional_map()
      |> finalize_workflows_by_type(
        active_states,
        terminal_states,
        state_phase_map,
        policy_by_route_key
      )

    merged_active_states = merge_workflow_state_lists(active_states, workflows_by_type, "active_states")
    merged_terminal_states = merge_workflow_state_lists(terminal_states, workflows_by_type, "terminal_states")
    merged_state_phase_map = merge_workflow_state_phase_maps(state_phase_map, workflows_by_type)

    %{
      tracker
      | endpoint: endpoint,
        auth: compact_map(auth),
        provider: compact_map(provider),
        lifecycle:
          compact_map(%{
            "active_states" => merged_active_states,
            "terminal_states" => merged_terminal_states,
            "state_phase_map" => merged_state_phase_map,
            "workflow_profile" => workflow_profile,
            "raw_state_by_route_key" => raw_state_by_route_key,
            "policy_by_route_key" => policy_by_route_key,
            "workflows_by_type" => workflows_by_type
          })
    }
  end

  defp normalize_default_map(value) when is_map(value), do: InputNormalizer.normalize_keys(value)
  defp normalize_default_map(_value), do: %{}

  defp workflow_profile(%{profile: profile}) when is_map(profile), do: InputNormalizer.normalize_keys(profile)
  defp workflow_profile(_workflow), do: nil

  defp merge_section(defaults, section) when is_map(defaults) and is_map(section) do
    Map.merge(defaults, InputNormalizer.normalize_keys(section))
  end

  defp merge_section(defaults, _section) when is_map(defaults), do: defaults

  defp default_if_empty(nil, defaults), do: defaults
  defp default_if_empty(values, _defaults), do: values

  defp compact_map(values) when is_map(values) do
    Enum.reduce(values, %{}, fn
      {_key, nil}, acc ->
        acc

      {_key, value}, acc when is_map(value) and map_size(value) == 0 ->
        acc

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp finalize_section(values, env_vars) when is_map(values) do
    values
    |> resolve_env_references()
    |> apply_env_var_defaults(env_vars)
  end

  defp normalize_secret_values(values) when is_map(values) do
    Enum.reduce(values, %{}, fn {key, value}, acc ->
      Map.put(acc, key, normalize_secret_values(value))
    end)
  end

  defp normalize_secret_values(value) when is_binary(value) do
    InputNormalizer.resolve_secret_setting(value, nil)
  end

  defp normalize_secret_values(value), do: value

  defp resolve_env_references(values) when is_map(values) do
    Enum.reduce(values, %{}, fn {key, value}, acc ->
      Map.put(acc, key, resolve_env_references(value))
    end)
  end

  defp resolve_env_references(value) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} -> System.get_env(env_name)
      :error -> value
    end
  end

  defp resolve_env_references(value), do: value

  defp env_reference_name("$" <> env_name) do
    if String.match?(env_name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp env_reference_name(_value), do: :error

  defp apply_env_var_defaults(values, env_vars)
       when is_map(values) and is_map(env_vars) do
    Enum.reduce(env_vars, values, fn {key, env_config}, acc ->
      normalized_key = to_string(key)
      current_value = Map.get(acc, normalized_key)

      resolved_value =
        case env_config do
          nested_env_vars when is_map(nested_env_vars) ->
            current_value
            |> normalize_default_map()
            |> apply_env_var_defaults(nested_env_vars)

          env_name when is_binary(env_name) ->
            apply_env_var_default(current_value, env_name)

          _ ->
            current_value
        end

      Map.put(acc, normalized_key, resolved_value)
    end)
  end

  defp apply_env_var_defaults(values, _env_vars), do: values

  defp apply_env_var_default(nil, env_name) when is_binary(env_name), do: System.get_env(env_name)
  defp apply_env_var_default(current_value, _env_name), do: current_value

  defp finalize_workflows_by_type(
         nil,
         _active_states,
         _terminal_states,
         _state_phase_map,
         _policy_by_route_key
       ),
       do: %{}

  defp finalize_workflows_by_type(
         workflows_by_type,
         active_states,
         terminal_states,
         state_phase_map,
         policy_by_route_key
       )
       when is_map(workflows_by_type) do
    Enum.reduce(workflows_by_type, %{}, fn {workitem_type_id, workflow}, acc ->
      normalized_workflow =
        case workflow do
          workflow_map when is_map(workflow_map) ->
            normalized_workflow = InputNormalizer.normalize_keys(workflow_map)

            %{
              "active_states" => default_if_empty(Map.get(normalized_workflow, "active_states"), active_states),
              "terminal_states" => default_if_empty(Map.get(normalized_workflow, "terminal_states"), terminal_states),
              "state_phase_map" =>
                normalized_workflow
                |> Map.get("state_phase_map")
                |> default_if_empty(state_phase_map)
                |> WorkflowLifecycle.normalize_state_phase_map(),
              "raw_state_by_route_key" =>
                normalized_workflow
                |> Map.get("raw_state_by_route_key")
                |> InputNormalizer.normalize_optional_map(),
              "policy_by_route_key" =>
                normalized_workflow
                |> Map.get("policy_by_route_key")
                |> default_if_empty(policy_by_route_key)
                |> InputNormalizer.normalize_optional_map()
            }

          _ ->
            %{}
        end

      Map.put(acc, to_string(workitem_type_id), normalized_workflow)
    end)
  end

  defp merge_workflow_state_lists(base_states, workflows_by_type, field_name)
       when is_map(workflows_by_type) and is_binary(field_name) do
    workflows_by_type
    |> Map.values()
    |> Enum.reduce(List.wrap(base_states), fn workflow, acc ->
      acc ++ List.wrap(Map.get(workflow, field_name))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp merge_workflow_state_lists(base_states, _workflows_by_type, _field_name),
    do: List.wrap(base_states)

  defp merge_workflow_state_phase_maps(base_state_phase_map, workflows_by_type)
       when is_map(workflows_by_type) do
    Enum.reduce(workflows_by_type, base_state_phase_map, fn {_workitem_type_id, workflow}, acc ->
      Map.merge(acc, Map.get(workflow, "state_phase_map", %{}))
    end)
  end

  defp merge_workflow_state_phase_maps(base_state_phase_map, _workflows_by_type),
    do: base_state_phase_map
end
