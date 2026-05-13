defmodule SymphonyElixir.Tracker.Tapd.WorkflowConfig do
  @moduledoc false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Workflow.Effective
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy, as: WorkflowRoutePolicy

  @type workflow :: Effective.t()

  @spec default_raw_state_by_route_key(module()) :: map()
  def default_raw_state_by_route_key(profile_module \\ ProfileRegistry.default_profile_module()) do
    profile_module.default_raw_state_by_route_key()
  end

  @spec route_keys(module()) :: [atom()]
  def route_keys(profile_module \\ ProfileRegistry.default_profile_module()), do: Map.keys(default_raw_state_by_route_key(profile_module))

  @spec resolve_raw_state_by_route_key(map() | nil, map() | nil, module()) :: map()
  def resolve_raw_state_by_route_key(
        raw_state_by_route_key,
        base_raw_state_by_route_key \\ nil,
        profile_module \\ ProfileRegistry.default_profile_module()
      ) do
    base = base_raw_state_by_route_key || default_raw_state_by_route_key(profile_module)

    base
    |> normalize_raw_state_by_route_key(profile_module)
    |> merge_raw_state_by_route_key(raw_state_by_route_key, profile_module)
  end

  @spec workflow_profile(map()) :: map()
  def workflow_profile(tracker) when is_map(tracker) do
    tracker
    |> lifecycle_map("workflow_profile")
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

  @spec configured_workflows_by_type(map()) :: %{String.t() => workflow()}
  def configured_workflows_by_type(tracker) when is_map(tracker) do
    profile_context = profile_context(tracker)
    profile_module = profile_context.module
    profile_options = profile_context.options

    base_raw_state_by_route_key =
      resolve_raw_state_by_route_key(
        lifecycle_map(tracker, "raw_state_by_route_key"),
        nil,
        profile_module
      )

    base_policy_by_route_key =
      WorkflowRoutePolicy.resolve_policy_by_route_key(
        lifecycle_map(tracker, "policy_by_route_key"),
        ProfileRegistry.default_policy_by_route_key(profile_module, profile_options),
        profile_module
      )

    tracker
    |> lifecycle_map("workflows_by_type")
    |> normalize_workflows_by_type(base_raw_state_by_route_key, base_policy_by_route_key, profile_context)
  end

  def configured_workflows_by_type(_tracker), do: %{}

  @spec configured_workitem_type_ids(map()) :: [String.t()]
  def configured_workitem_type_ids(tracker) when is_map(tracker) do
    workflows_by_type = configured_workflows_by_type(tracker)

    if map_size(workflows_by_type) > 0 do
      Map.keys(workflows_by_type)
    else
      configured_platform_workitem_type_ids(tracker)
    end
  end

  def configured_workitem_type_ids(_tracker), do: []

  @spec request_workitem_type_id(map()) :: String.t() | nil
  def request_workitem_type_id(tracker) when is_map(tracker) do
    case configured_workitem_type_ids(tracker) do
      [workitem_type_id] -> workitem_type_id
      _ -> nil
    end
  end

  def request_workitem_type_id(_tracker), do: nil

  @spec workflow_for_story(map(), map()) :: workflow() | nil
  def workflow_for_story(tracker, story) when is_map(tracker) and is_map(story) do
    story
    |> string_field("workitem_type_id")
    |> normalize_string()
    |> then(&workflow_for_workitem_type(tracker, &1))
  end

  def workflow_for_story(_tracker, _story), do: nil

  @spec workflow_for_workitem_type(map(), String.t() | nil) :: workflow() | nil
  def workflow_for_workitem_type(tracker, workitem_type_id) when is_map(tracker) do
    workflows_by_type = configured_workflows_by_type(tracker)

    cond do
      is_binary(workitem_type_id) and Map.has_key?(workflows_by_type, workitem_type_id) ->
        Map.get(workflows_by_type, workitem_type_id)

      map_size(workflows_by_type) > 0 ->
        nil

      true ->
        global_workflow(tracker, workitem_type_id)
    end
  end

  def workflow_for_workitem_type(_tracker, _workitem_type_id), do: nil

  @spec global_workflow(map(), String.t() | nil) :: workflow()
  def global_workflow(tracker, workitem_type_id \\ nil)

  def global_workflow(tracker, workitem_type_id) when is_map(tracker) do
    profile_context = profile_context(tracker)
    profile_module = profile_context.module
    profile_options = profile_context.options

    %{
      workitem_type_id: workitem_type_id,
      active_states: List.wrap(TrackerConfig.active_states(tracker)),
      terminal_states: List.wrap(TrackerConfig.terminal_states(tracker)),
      state_phase_map: TrackerConfig.state_phase_map(tracker) || %{},
      raw_state_by_route_key:
        resolve_raw_state_by_route_key(
          lifecycle_map(tracker, "raw_state_by_route_key"),
          nil,
          profile_module
        ),
      policy_by_route_key:
        WorkflowRoutePolicy.resolve_policy_by_route_key(
          lifecycle_map(tracker, "policy_by_route_key"),
          ProfileRegistry.default_policy_by_route_key(profile_module, profile_options),
          profile_module
        )
    }
    |> effective_workflow(profile_context)
  end

  def global_workflow(_tracker, workitem_type_id) do
    profile_context = ProfileRegistry.resolve!(nil)
    profile_module = profile_context.module
    profile_options = profile_context.options

    %{
      workitem_type_id: workitem_type_id,
      active_states: [],
      terminal_states: [],
      state_phase_map: %{},
      raw_state_by_route_key: default_raw_state_by_route_key(profile_module),
      policy_by_route_key: ProfileRegistry.default_policy_by_route_key(profile_module, profile_options)
    }
    |> effective_workflow(profile_context)
  end

  defp normalize_workflows_by_type(
         workflows_by_type,
         base_raw_state_by_route_key,
         base_policy_by_route_key,
         profile_context
       )
       when is_map(workflows_by_type) do
    Enum.reduce(workflows_by_type, %{}, fn {workitem_type_id, workflow}, acc ->
      normalized_workitem_type_id = normalize_string(workitem_type_id)

      if is_nil(normalized_workitem_type_id) do
        acc
      else
        Map.put(
          acc,
          normalized_workitem_type_id,
          normalize_workflow(
            workflow,
            normalized_workitem_type_id,
            base_raw_state_by_route_key,
            base_policy_by_route_key,
            profile_context
          )
        )
      end
    end)
  end

  defp normalize_workflow(
         workflow,
         workitem_type_id,
         base_raw_state_by_route_key,
         base_policy_by_route_key,
         profile_context
       )
       when is_map(workflow) do
    profile_module = profile_context.module

    %{
      workitem_type_id: workitem_type_id,
      active_states: normalize_state_list(string_field(workflow, "active_states")),
      terminal_states: normalize_state_list(string_field(workflow, "terminal_states")),
      state_phase_map:
        workflow
        |> string_field("state_phase_map")
        |> case do
          state_phase_map when is_map(state_phase_map) -> WorkflowLifecycle.normalize_state_phase_map(state_phase_map)
          _ -> %{}
        end,
      raw_state_by_route_key:
        workflow
        |> string_field("raw_state_by_route_key")
        |> resolve_raw_state_by_route_key(base_raw_state_by_route_key, profile_module),
      policy_by_route_key:
        workflow
        |> string_field("policy_by_route_key")
        |> WorkflowRoutePolicy.resolve_policy_by_route_key(base_policy_by_route_key, profile_module)
    }
    |> effective_workflow(profile_context)
  end

  defp normalize_workflow(
         _workflow,
         workitem_type_id,
         base_raw_state_by_route_key,
         base_policy_by_route_key,
         profile_context
       ) do
    %{
      workitem_type_id: workitem_type_id,
      active_states: [],
      terminal_states: [],
      state_phase_map: %{},
      raw_state_by_route_key: base_raw_state_by_route_key,
      policy_by_route_key: base_policy_by_route_key
    }
    |> effective_workflow(profile_context)
  end

  defp normalize_state_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_state_list(_values), do: []

  defp normalize_raw_state_by_route_key(raw_state_by_route_key, profile_module) when is_map(raw_state_by_route_key) do
    default_raw_state_by_route_key = default_raw_state_by_route_key(profile_module)

    Enum.reduce(default_raw_state_by_route_key, default_raw_state_by_route_key, fn {route_key, default_state}, acc ->
      normalized_state =
        raw_state_by_route_key
        |> string_field(Atom.to_string(route_key))
        |> normalize_string()

      Map.put(acc, route_key, normalized_state || default_state)
    end)
  end

  defp normalize_raw_state_by_route_key(_raw_state_by_route_key, profile_module),
    do: default_raw_state_by_route_key(profile_module)

  defp merge_raw_state_by_route_key(base_raw_state_by_route_key, raw_state_by_route_key, profile_module) when is_map(raw_state_by_route_key) do
    Enum.reduce(default_raw_state_by_route_key(profile_module), base_raw_state_by_route_key, fn {route_key, _default_state}, acc ->
      normalized_state =
        raw_state_by_route_key
        |> string_field(Atom.to_string(route_key))
        |> normalize_string()

      if is_nil(normalized_state) do
        acc
      else
        Map.put(acc, route_key, normalized_state)
      end
    end)
  end

  defp merge_raw_state_by_route_key(base_raw_state_by_route_key, _raw_state_by_route_key, _profile_module),
    do: base_raw_state_by_route_key

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

  defp effective_workflow(attrs, profile_context) when is_map(attrs) do
    attrs
    |> Map.merge(workflow_facts(profile_context))
    |> Effective.new!()
  end

  defp configured_platform_workitem_type_ids(tracker) do
    platform = platform(tracker)

    plural_ids =
      case string_field(platform, "workitem_type_ids") do
        values when is_list(values) -> values
        _ -> []
      end

    singular_ids =
      platform
      |> string_field("workitem_type_id")
      |> List.wrap()

    (plural_ids ++ singular_ids)
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp string_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp lifecycle_map(tracker, key) when is_map(tracker) and is_binary(key) do
    tracker
    |> TrackerConfig.lifecycle()
    |> string_field(key)
    |> case do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp platform(tracker) when is_map(tracker) do
    tracker
    |> TrackerConfig.provider()
    |> string_field("platform")
    |> case do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(value), do: if(value in [nil, ""], do: nil, else: to_string(value))
end
