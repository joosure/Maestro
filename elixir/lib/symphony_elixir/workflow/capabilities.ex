defmodule SymphonyElixir.Workflow.Capabilities do
  @moduledoc """
  Validates workflow-profile capability requirements against a supplied
  deployment capability set.
  """

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy

  @type capability :: String.t()
  @type provider_family :: :tracker | :repo | :repo_provider | :agent_provider | :unknown

  @spec validate_required_capabilities(map(), Enumerable.t()) :: :ok | {:error, term()}
  def validate_required_capabilities(settings, available_capabilities) when is_map(settings) do
    with {:ok, required_capabilities, profile_context} <- required_capabilities(settings) do
      available_capabilities = normalize_available_capabilities(available_capabilities)

      case Enum.find(required_capabilities, &(not MapSet.member?(available_capabilities, &1))) do
        nil ->
          :ok

        missing_capability ->
          {:error, {:missing_workflow_capability, profile_context.kind, profile_context.version, missing_capability, provider_family(missing_capability)}}
      end
    end
  end

  @spec required_capabilities(map()) ::
          {:ok, [capability()], ProfileRegistry.resolved_profile()} | {:error, term()}
  def required_capabilities(settings) when is_map(settings) do
    with {:ok, profile_context} <- profile_context(settings) do
      required_capabilities =
        settings
        |> required_capabilities_for_profile(profile_context)
        |> Enum.uniq()

      {:ok, required_capabilities, profile_context}
    end
  end

  @spec required_capabilities_for_issue(map(), map() | nil) ::
          {:ok, [capability()], ProfileRegistry.resolved_profile()} | {:error, term()}
  def required_capabilities_for_issue(settings, issue) when is_map(settings) do
    with {:ok, profile_context} <- profile_context(settings) do
      required_capabilities =
        settings
        |> required_capabilities_for_profile_issue(profile_context, issue)
        |> Enum.uniq()

      {:ok, required_capabilities, profile_context}
    end
  end

  defp profile_context(settings) do
    settings
    |> map_field(:workflow)
    |> map_field(:profile)
    |> ProfileRegistry.resolve()
  end

  defp required_capabilities_for_profile(settings, %{module: profile_module, options: profile_options} = profile_context) do
    profile_capabilities = ProfileRegistry.required_capabilities(profile_module, profile_options)
    execution_profile_capabilities = selected_execution_profile_capabilities(settings, profile_context)

    profile_capabilities ++ execution_profile_capabilities
  end

  defp required_capabilities_for_profile_issue(settings, %{module: profile_module, options: profile_options} = profile_context, issue) do
    profile_capabilities = ProfileRegistry.required_capabilities(profile_module, profile_options)
    current_execution_profile_capabilities = current_execution_profile_capabilities(settings, profile_context, issue)

    profile_capabilities ++ current_execution_profile_capabilities
  end

  defp selected_execution_profile_capabilities(settings, profile_context) do
    settings
    |> ExecutionProfileRegistry.selected_execution_profiles(profile_context)
    |> Enum.flat_map(fn %{execution_profile: execution_profile, action: action} ->
      ExecutionProfileRegistry.required_capabilities(profile_context, execution_profile, action)
    end)
  end

  defp current_execution_profile_capabilities(settings, profile_context, issue)
       when is_map(issue) do
    case current_route_policy(settings, profile_context, issue) do
      %{action: :dispatch, execution_profile: execution_profile} when is_binary(execution_profile) ->
        ExecutionProfileRegistry.required_capabilities(profile_context, execution_profile, :dispatch)

      _route_policy ->
        []
    end
  end

  defp current_execution_profile_capabilities(_settings, _profile_context, _issue), do: []

  defp current_route_policy(settings, %{module: profile_module, options: profile_options}, issue) when is_map(issue) do
    policy_by_route_key = effective_policy_by_route_key(settings, profile_module, profile_options, issue)

    case current_route_key(settings, profile_module, issue, policy_by_route_key) do
      nil ->
        nil

      route_key ->
        RoutePolicy.policy_for_route_key(policy_by_route_key, route_key)
    end
  end

  defp current_route_key(settings, profile_module, issue, policy_by_route_key) when is_map(issue) do
    raw_state_by_route_key = effective_raw_state_by_route_key(settings, profile_module, issue, policy_by_route_key)
    raw_route_key = RoutePolicy.route_key_for_raw_state(Map.get(issue, :state), raw_state_by_route_key, profile_module)

    raw_route_key || route_key_for_lifecycle_phase(settings, profile_module, issue)
  end

  defp route_key_for_lifecycle_phase(settings, profile_module, issue) do
    phase =
      Map.get(issue, :lifecycle_phase) ||
        WorkflowLifecycle.phase_for_state(
          Map.get(issue, :state),
          effective_state_phase_map(settings, issue)
        )

    normalized_phase = WorkflowLifecycle.normalize_phase(phase)
    phases_by_route_key = profile_module.lifecycle_phase_by_route_key()

    Enum.find_value(phases_by_route_key, fn {route_key, route_phase} ->
      if WorkflowLifecycle.normalize_phase(route_phase) == normalized_phase, do: route_key
    end)
  end

  defp effective_policy_by_route_key(settings, profile_module, profile_options, issue) do
    lifecycle = settings |> map_field(:tracker) |> map_field(:lifecycle)
    default_policy_by_route_key = ProfileRegistry.default_policy_by_route_key(profile_module, profile_options)

    lifecycle
    |> map_field(:policy_by_route_key)
    |> RoutePolicy.resolve_policy_by_route_key(default_policy_by_route_key, profile_module)
    |> then(fn policy_by_route_key ->
      issue
      |> IssueContext.workflow_map(%{})
      |> map_field(:policy_by_route_key)
      |> RoutePolicy.merge_effective_policy_by_route_key(policy_by_route_key, profile_module)
    end)
  end

  defp effective_raw_state_by_route_key(settings, profile_module, issue, policy_by_route_key) do
    lifecycle = settings |> map_field(:tracker) |> map_field(:lifecycle)
    identity_raw_state_map = RoutePolicy.identity_raw_state_by_route_key(profile_module)

    lifecycle
    |> map_field(:raw_state_by_route_key)
    |> RoutePolicy.resolve_raw_state_by_route_key(identity_raw_state_map, profile_module, policy_by_route_key)
    |> then(fn raw_state_by_route_key ->
      issue
      |> IssueContext.workflow_map(%{})
      |> map_field(:raw_state_by_route_key)
      |> RoutePolicy.merge_effective_raw_state_by_route_key(raw_state_by_route_key, profile_module, policy_by_route_key)
    end)
    |> RoutePolicy.remove_disabled_raw_states(policy_by_route_key, profile_module)
  end

  defp effective_state_phase_map(settings, issue) do
    lifecycle = settings |> map_field(:tracker) |> map_field(:lifecycle)
    settings_state_phase_map = lifecycle |> map_field(:state_phase_map) |> WorkflowLifecycle.normalize_state_phase_map()

    issue
    |> IssueContext.workflow_map(%{})
    |> map_field(:state_phase_map)
    |> case do
      state_phase_map when is_map(state_phase_map) -> WorkflowLifecycle.normalize_state_phase_map(state_phase_map)
      _state_phase_map -> settings_state_phase_map
    end
  end

  defp provider_family("tracker." <> _rest), do: :tracker
  defp provider_family("repo_provider." <> _rest), do: :repo_provider
  defp provider_family("repo." <> _rest), do: :repo
  defp provider_family("agent." <> _rest), do: :agent_provider
  defp provider_family(_capability), do: :unknown

  defp normalize_available_capabilities(available_capabilities) do
    available_capabilities
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil
end
