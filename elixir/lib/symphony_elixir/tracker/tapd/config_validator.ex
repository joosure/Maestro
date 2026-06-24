defmodule SymphonyElixir.Tracker.Tapd.ConfigValidator do
  @moduledoc """
  Deep validation for TAPD tracker configuration.

  Validates profile route-key maps, workflow-by-type consistency, route policy
  correctness, and state phase map coherence. Called by `Tapd.Adapter`
  after basic credential checks pass.
  """

  import SymphonyElixir.Tracker.ConfigAccess, only: [map_field: 2, normalize_optional_map: 1]

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.Tapd.WorkflowConfig
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Validator, as: WorkflowValidator

  @provider_kind Kinds.tapd()

  @workflow_by_type_fields MapSet.new([
                             "active_states",
                             "terminal_states",
                             "state_phase_map",
                             "raw_state_by_route_key",
                             "policy_by_route_key"
                           ])

  @spec validate(map(), map()) :: :ok | {:error, term()}
  def validate(tracker, platform) when is_map(tracker) and is_map(platform) do
    workflows_by_type = WorkflowConfig.configured_workflows_by_type(tracker)

    result =
      cond do
        map_size(workflows_by_type) == 0 and blank_state_list?(TrackerConfig.active_states(tracker)) ->
          {:error, :missing_tapd_active_states}

        map_size(workflows_by_type) == 0 and blank_state_list?(TrackerConfig.terminal_states(tracker)) ->
          {:error, :missing_tapd_terminal_states}

        invalid_optional_platform_value?(platform, "workitem_type_id") ->
          {:error, :invalid_tapd_workitem_type_id}

        invalid_optional_workitem_type_ids?(platform) ->
          {:error, :invalid_tapd_workitem_type_ids}

        invalid_optional_platform_value?(platform, "comment_author") ->
          {:error, :invalid_tapd_comment_author}

        true ->
          with :ok <- validate_global_state_phase_map(tracker),
               :ok <- validate_workflow_profile_config(tracker),
               :ok <- validate_global_raw_state_by_route_key_config(tracker),
               :ok <- validate_workflows_by_type_config(tracker, platform) do
            :ok
          end
      end

    normalize_validate_config_result(result)
  end

  # ── Global state phase map validation ───────────────────────────

  defp validate_global_state_phase_map(tracker) when is_map(tracker) do
    workflow_tracker = %{
      active_states: List.wrap(TrackerConfig.active_states(tracker)),
      terminal_states: List.wrap(TrackerConfig.terminal_states(tracker)),
      state_phase_map: TrackerConfig.state_phase_map(tracker) || %{}
    }

    case WorkflowLifecycle.validate_state_phase_map(workflow_tracker) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_tapd_state_phase_map, reason}}
    end
  end

  # ── Workflow profile validation ─────────────────────────────────

  defp validate_workflow_profile_config(tracker) when is_map(tracker) do
    case ProfileRegistry.resolve(WorkflowConfig.workflow_profile(tracker)) do
      {:ok, _resolved_profile} -> :ok
      {:error, reason} -> {:error, {:invalid_workflow_profile, reason}}
    end
  end

  # ── State list validation ────────────────────────────────────────

  defp blank_state_list?(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> true
      _normalized_states -> false
    end
  end

  defp blank_state_list?(_values), do: true

  # ── Platform value validation ────────────────────────────────────

  defp invalid_optional_platform_value?(platform, key) when is_map(platform) do
    case platform_value(platform, key) do
      nil -> false
      value when is_binary(value) -> String.trim(value) == ""
      _ -> true
    end
  end

  defp invalid_optional_workitem_type_ids?(platform) when is_map(platform) do
    case platform_value(platform, "workitem_type_ids") do
      nil ->
        false

      values when is_list(values) ->
        normalized_values =
          values
          |> Enum.map(&normalize_optional_platform_string/1)
          |> Enum.reject(&is_nil/1)

        normalized_values == [] or length(normalized_values) != length(values)

      _ ->
        true
    end
  end

  # ── Raw-state route map config ───────────────────────────────────

  defp validate_global_raw_state_by_route_key_config(tracker) when is_map(tracker) do
    profile_context = WorkflowConfig.profile_context(tracker)
    profile_module = profile_context.module
    raw_state_by_route_key = lifecycle_map(tracker, "raw_state_by_route_key")
    policy_by_route_key = lifecycle_map(tracker, "policy_by_route_key")

    with :ok <- WorkflowValidator.validate_raw_state_by_route_key_entries(:global, raw_state_by_route_key, profile_module),
         :ok <- WorkflowValidator.validate_policy_by_route_key_entries(:global, policy_by_route_key, profile_context) do
      if map_size(raw_state_by_route_key) == 0 and map_size(policy_by_route_key) == 0 do
        :ok
      else
        workflow = WorkflowConfig.global_workflow(tracker)

        case WorkflowValidator.validate_workflow(:global, workflow) do
          :ok -> :ok
          {:error, reason} -> {:error, {:invalid_tapd_raw_state_by_route_key, reason}}
        end
      end
    else
      {:error, reason} -> {:error, {:invalid_tapd_raw_state_by_route_key, reason}}
    end
  end

  # ── Workflows by type config ─────────────────────────────────────

  defp validate_workflows_by_type_config(tracker, platform)
       when is_map(tracker) and is_map(platform) do
    workflows_by_type = WorkflowConfig.configured_workflows_by_type(tracker)
    raw_workflows_by_type = lifecycle_map(tracker, "workflows_by_type")

    cond do
      map_size(workflows_by_type) == 0 ->
        :ok

      platform_has_explicit_workitem_scope?(platform) ->
        {:error, :conflicting_tapd_workitem_type_scope}

      true ->
        profile_context = WorkflowConfig.profile_context(tracker)
        profile_module = profile_context.module

        with :ok <- validate_raw_workflows_by_type_fields(raw_workflows_by_type),
             :ok <- validate_raw_workflows_by_type_raw_state_entries(raw_workflows_by_type, profile_module),
             :ok <- validate_raw_workflows_by_type_policy_entries(raw_workflows_by_type, profile_context),
             :ok <- validate_workflows_by_type_entries(workflows_by_type),
             :ok <- validate_workflows_by_type_state_phase_consistency(workflows_by_type) do
          :ok
        end
    end
  end

  defp validate_workflows_by_type_config(_tracker, _platform), do: :ok

  defp validate_workflows_by_type_entries(workflows_by_type) when is_map(workflows_by_type) do
    Enum.reduce_while(workflows_by_type, :ok, fn {workitem_type_id, workflow}, :ok ->
      case validate_workflows_by_type_entry(workitem_type_id, workflow) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_workflows_by_type_entry(workitem_type_id, workflow)
       when is_binary(workitem_type_id) and is_map(workflow) do
    workflow_tracker = %{
      active_states: Map.get(workflow, :active_states, []),
      terminal_states: Map.get(workflow, :terminal_states, []),
      state_phase_map: Map.get(workflow, :state_phase_map, %{})
    }

    with :ok <- WorkflowLifecycle.validate_state_phase_map(workflow_tracker),
         :ok <- WorkflowValidator.validate_workflow(workitem_type_id, workflow) do
      :ok
    else
      {:error, reason} ->
        {:error, {:invalid_tapd_workflows_by_type, workitem_type_id, reason}}
    end
  end

  defp validate_workflows_by_type_entry(workitem_type_id, _workflow) do
    {:error, {:invalid_tapd_workflows_by_type, workitem_type_id, :invalid_workflow_entry}}
  end

  defp validate_raw_workflows_by_type_fields(workflows_by_type)
       when is_map(workflows_by_type) do
    Enum.reduce_while(workflows_by_type, :ok, fn {workitem_type_id, workflow}, :ok ->
      case workflow do
        workflow_map when is_map(workflow_map) ->
          case unsupported_workflow_by_type_field(workflow_map) do
            nil ->
              {:cont, :ok}

            field ->
              {:halt, {:error, {:invalid_tapd_workflows_by_type, to_string(workitem_type_id), {:unsupported_workflow_field, field}}}}
          end

        _workflow ->
          {:cont, :ok}
      end
    end)
  end

  defp unsupported_workflow_by_type_field(workflow_map) when is_map(workflow_map) do
    Enum.find(Map.keys(workflow_map), fn key ->
      key
      |> normalize_config_field_name()
      |> then(&(not MapSet.member?(@workflow_by_type_fields, &1)))
    end)
  end

  defp normalize_config_field_name(key) when is_binary(key), do: key
  defp normalize_config_field_name(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_config_field_name(key), do: key

  defp validate_raw_workflows_by_type_raw_state_entries(workflows_by_type, profile_module)
       when is_map(workflows_by_type) do
    Enum.reduce_while(workflows_by_type, :ok, fn {workitem_type_id, workflow}, :ok ->
      raw_state_by_route_key =
        case workflow do
          workflow_map when is_map(workflow_map) ->
            raw_workflow_field(workflow_map, "raw_state_by_route_key")

          _ ->
            nil
        end

      case WorkflowValidator.validate_raw_state_by_route_key_entries(to_string(workitem_type_id), raw_state_by_route_key, profile_module) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_tapd_workflows_by_type, to_string(workitem_type_id), reason}}}
      end
    end)
  end

  defp validate_raw_workflows_by_type_policy_entries(workflows_by_type, profile_context)
       when is_map(workflows_by_type) do
    Enum.reduce_while(workflows_by_type, :ok, fn {workitem_type_id, workflow}, :ok ->
      policy_by_route_key =
        case workflow do
          workflow_map when is_map(workflow_map) ->
            raw_workflow_field(workflow_map, "policy_by_route_key")

          _ ->
            nil
        end

      case WorkflowValidator.validate_policy_by_route_key_entries(to_string(workitem_type_id), policy_by_route_key, profile_context) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_tapd_workflows_by_type, to_string(workitem_type_id), reason}}}
      end
    end)
  end

  # ── State phase consistency ─────────────────────────────────────

  defp validate_workflows_by_type_state_phase_consistency(workflows_by_type)
       when is_map(workflows_by_type) do
    Enum.reduce_while(workflows_by_type, %{}, fn {workitem_type_id, workflow}, acc ->
      case Enum.reduce_while(Map.get(workflow, :state_phase_map, %{}), {:ok, acc}, fn
             {state_name, phase_name}, {:ok, phase_acc} ->
               case Map.get(phase_acc, state_name) do
                 nil ->
                   {:cont, {:ok, Map.put(phase_acc, state_name, phase_name)}}

                 ^phase_name ->
                   {:cont, {:ok, phase_acc}}

                 existing_phase ->
                   {:halt, {:error, {:invalid_tapd_workflows_by_type, workitem_type_id, {:conflicting_state_phase_mapping, state_name, existing_phase, phase_name}}}}
               end
           end) do
        {:ok, updated_acc} -> {:cont, updated_acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      %{} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Error normalization ─────────────────────────────────────────

  defp normalize_validate_config_result(:ok), do: :ok

  defp normalize_validate_config_result({:error, reason}) do
    {:error, validate_config_error(reason)}
  end

  defp validate_config_error(:missing_tapd_active_states) do
    config_error(:missing_tapd_active_states, :invalid_configuration, "TAPD active states are required.")
  end

  defp validate_config_error(:missing_tapd_terminal_states) do
    config_error(:missing_tapd_terminal_states, :invalid_configuration, "TAPD terminal states are required.")
  end

  defp validate_config_error({:invalid_tapd_state_phase_map, {:invalid_tracker_state_phase_map, {:missing_mapping, state}}}) do
    config_error(
      {:invalid_tapd_state_phase_map, {:missing_mapping, state}},
      :invalid_configuration,
      "TAPD active/terminal state '#{state}' is missing its mapping in state_phase_map. " <>
        "Please add a mapping under tracker.lifecycle.state_phase_map, e.g. '#{state}: in_progress'."
    )
  end

  defp validate_config_error({:invalid_tapd_state_phase_map, {:invalid_tracker_state_phase_map, {:invalid_phase, state, phase}}}) do
    config_error(
      {:invalid_tapd_state_phase_map, {:invalid_phase, state, phase}},
      :invalid_configuration,
      "TAPD state '#{state}' is mapped to an invalid phase '#{phase}'. " <>
        "Please check tracker.lifecycle.state_phase_map."
    )
  end

  defp validate_config_error({:invalid_tapd_state_phase_map, :missing_tracker_state_phase_map}) do
    config_error(
      :missing_tracker_state_phase_map,
      :invalid_configuration,
      "TAPD state_phase_map is required when active/terminal states are defined."
    )
  end

  defp validate_config_error(reason)
       when reason in [
              :invalid_tapd_workitem_type_id,
              :invalid_tapd_workitem_type_ids,
              :invalid_tapd_comment_author,
              :conflicting_tapd_workitem_type_scope
            ] do
    config_error(reason, :invalid_configuration, "TAPD configuration is invalid or incomplete.")
  end

  defp validate_config_error(reason) do
    config_error(reason, :invalid_configuration, "TAPD configuration is invalid or incomplete.")
  end

  defp config_error(source_reason, code, message) do
    Error.new(%{
      provider: @provider_kind,
      operation: :validate_config,
      code: code,
      message: message,
      details: %{source_reason: source_reason}
    })
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp platform_has_explicit_workitem_scope?(platform) when is_map(platform) do
    platform_value(platform, "workitem_type_id") not in [nil, ""] or
      platform_value(platform, "workitem_type_ids") not in [nil, []]
  end

  defp platform_value(platform, key) when is_map(platform) and is_binary(key) do
    Map.get(platform, key) || Map.get(platform, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(platform, key)
  end

  defp lifecycle_map(tracker, key) when is_map(tracker) and is_binary(key) do
    tracker
    |> TrackerConfig.lifecycle()
    |> map_field(key)
    |> normalize_optional_map()
  end

  defp raw_workflow_field(workflow_map, key) when is_map(workflow_map) and is_binary(key) do
    Map.get(workflow_map, key)
  end

  defp normalize_optional_platform_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_platform_string(_value), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(_value), do: nil
end
