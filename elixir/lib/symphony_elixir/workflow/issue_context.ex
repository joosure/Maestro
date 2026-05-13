defmodule SymphonyElixir.Workflow.IssueContext do
  @moduledoc """
  Extracts workflow facts from normalized issue-like data.
  """

  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RouteFacts

  @type issue_like :: map()

  @spec workflow_map(issue_like(), map()) :: map()
  def workflow_map(issue, defaults \\ %{})

  def workflow_map(issue, defaults) when is_map(issue) and is_map(defaults) do
    case Map.get(issue, :workflow) do
      workflow when is_map(workflow) -> Map.merge(defaults, workflow)
      _other -> defaults
    end
  end

  def workflow_map(_issue, defaults) when is_map(defaults), do: defaults

  @spec active_states(issue_like(), [String.t()]) :: [String.t()]
  def active_states(issue, defaults \\ []) do
    issue
    |> workflow_map(%{})
    |> Map.get(:active_states, defaults)
    |> List.wrap()
  end

  @spec terminal_states(issue_like(), [String.t()]) :: [String.t()]
  def terminal_states(issue, defaults \\ []) do
    issue
    |> workflow_map(%{})
    |> Map.get(:terminal_states, defaults)
    |> List.wrap()
  end

  @spec state_phase_map(issue_like(), map()) :: map()
  def state_phase_map(issue, defaults \\ %{}) do
    issue
    |> workflow_map(%{})
    |> Map.get(:state_phase_map, defaults)
    |> case do
      state_phase_map when is_map(state_phase_map) -> state_phase_map
      _other -> defaults
    end
  end

  @spec raw_state_by_route_key(issue_like(), map() | nil) :: map() | nil
  def raw_state_by_route_key(issue, defaults \\ %{}) do
    issue
    |> workflow_map(%{})
    |> Map.get(:raw_state_by_route_key, defaults)
    |> case do
      raw_state_by_route_key when is_map(raw_state_by_route_key) -> raw_state_by_route_key
      _other -> defaults
    end
  end

  @spec policy_by_route_key(issue_like(), map() | nil) :: map() | nil
  def policy_by_route_key(issue, defaults \\ %{}) do
    issue
    |> workflow_map(%{})
    |> Map.get(:policy_by_route_key, defaults)
    |> case do
      policy_by_route_key when is_map(policy_by_route_key) -> policy_by_route_key
      _other -> defaults
    end
  end

  @spec profile(issue_like(), map()) :: map()
  def profile(issue, defaults \\ ProfileRegistry.default_profile_config()) do
    issue
    |> workflow_map(%{})
    |> Map.get(:profile, defaults)
    |> case do
      profile when is_map(profile) -> profile
      _other -> defaults
    end
  end

  @spec profile_context(issue_like()) :: ProfileRegistry.resolved_profile()
  def profile_context(issue) do
    issue
    |> profile()
    |> ProfileRegistry.resolve()
    |> case do
      {:ok, resolved_profile} -> resolved_profile
      {:error, _reason} -> ProfileRegistry.resolve!(nil)
    end
  end

  @spec route_facts(issue_like()) :: RouteFacts.t() | nil
  def route_facts(issue) when is_map(issue) do
    profile_context = profile_context(issue)

    RouteFacts.from_fields(%{
      state: Map.get(issue, :state),
      lifecycle_phase: Map.get(issue, :lifecycle_phase),
      state_phase_map: state_phase_map(issue, %{}),
      raw_state_by_route_key: raw_state_by_route_key(issue, nil),
      policy_by_route_key:
        policy_by_route_key(
          issue,
          ProfileRegistry.default_policy_by_route_key(profile_context.module, profile_context.options)
        ),
      profile_module: profile_context.module
    })
  end
end
