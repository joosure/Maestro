defmodule SymphonyElixir.Tracker.Linear.ConfigValidator do
  @moduledoc false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Tracker.Linear.WorkflowConfig
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Validator, as: WorkflowValidator

  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(tracker) when is_map(tracker) do
    result =
      with :ok <- validate_workflow_profile_config(tracker),
           :ok <- validate_global_route_map_config(tracker) do
        :ok
      end

    case result do
      :ok -> :ok
      {:error, reason} -> {:error, config_error(reason)}
    end
  end

  defp validate_workflow_profile_config(tracker) when is_map(tracker) do
    case ProfileRegistry.resolve(WorkflowConfig.workflow_profile(tracker)) do
      {:ok, _resolved_profile} -> :ok
      {:error, reason} -> {:error, {:invalid_workflow_profile, reason}}
    end
  end

  defp validate_global_route_map_config(tracker) when is_map(tracker) do
    profile_context = WorkflowConfig.profile_context(tracker)
    profile_module = profile_context.module
    raw_state_by_route_key = lifecycle_map(tracker) |> map_field(:raw_state_by_route_key)
    policy_by_route_key = lifecycle_map(tracker) |> map_field(:policy_by_route_key)

    with :ok <- WorkflowValidator.validate_raw_state_by_route_key_entries(:global, raw_state_by_route_key || %{}, profile_module),
         :ok <- validate_policy_by_route_key_entries(policy_by_route_key, profile_context),
         :ok <- maybe_validate_effective_workflow(tracker, raw_state_by_route_key) do
      :ok
    else
      {:error, reason} -> {:error, {:invalid_linear_workflow_config, reason}}
    end
  end

  defp validate_policy_by_route_key_entries(policy_by_route_key, profile_context) do
    case WorkflowValidator.validate_policy_by_route_key_entries(:global, policy_by_route_key || %{}, profile_context) do
      :ok -> :ok
      {:error, {:invalid_route_policy_execution_profile_action, :global, _route_key, _action}} -> :ok
      {:error, {:invalid_route_policy_execution_profile, :global, _route_key, _execution_profile}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_validate_effective_workflow(tracker, raw_state_by_route_key) do
    if configured_route_map?(raw_state_by_route_key) do
      WorkflowValidator.validate_workflow(:global, WorkflowConfig.global_workflow(tracker))
    else
      :ok
    end
  end

  defp configured_route_map?(value) when is_map(value), do: map_size(value) > 0
  defp configured_route_map?(_value), do: false

  defp lifecycle_map(tracker) when is_map(tracker) do
    TrackerConfig.lifecycle(tracker)
  end

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil

  defp config_error(source_reason) do
    Error.new(%{
      provider: "linear",
      operation: :validate_config,
      code: :invalid_configuration,
      message: "Linear workflow configuration is invalid.",
      details: %{source_reason: source_reason}
    })
  end
end
