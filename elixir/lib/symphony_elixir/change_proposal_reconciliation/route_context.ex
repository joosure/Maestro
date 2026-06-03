defmodule SymphonyElixir.ChangeProposalReconciliation.RouteContext do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig

  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy

  @type t :: %{
          required(:profile_context) => map(),
          required(:state_phase_map) => map(),
          required(:raw_state_by_route_key) => map(),
          required(:policy_by_route_key) => map()
        }

  @spec for_issue(map(), Issue.t()) :: t()
  def for_issue(settings, %Issue{} = issue) when is_map(settings) do
    case IssueContext.raw_state_by_route_key(issue, nil) do
      raw_state_by_route_key when is_map(raw_state_by_route_key) and map_size(raw_state_by_route_key) > 0 ->
        issue_route_context(issue, raw_state_by_route_key)

      _raw_state_by_route_key ->
        global_route_context(settings)
    end
  end

  @spec route_facts(Issue.t(), t() | map()) :: RouteFacts.t() | nil
  def route_facts(%Issue{} = issue, context) when is_map(context) do
    RouteFacts.from_fields(%{
      state: issue.state,
      lifecycle_phase: issue.lifecycle_phase,
      state_phase_map: context.state_phase_map,
      raw_state_by_route_key: context.raw_state_by_route_key,
      policy_by_route_key: context.policy_by_route_key,
      profile_module: context.profile_context.module
    })
  end

  @spec source_raw_states(map(), Config.t()) :: [String.t()]
  def source_raw_states(settings, %Config{} = config) when is_map(settings) do
    route_maps = configured_raw_state_route_maps(settings)

    config
    |> Config.source_route_keys()
    |> Enum.flat_map(fn route_key ->
      Enum.flat_map(route_maps, fn raw_state_by_route_key ->
        raw_state_by_route_key
        |> RoutePolicy.raw_state_for_route_key(route_key)
        |> List.wrap()
      end)
    end)
    |> Enum.filter(&present_string?/1)
    |> Enum.uniq()
  end

  defp issue_route_context(%Issue{} = issue, raw_state_by_route_key) do
    profile_context = IssueContext.profile_context(issue)

    %{
      profile_context: profile_context,
      state_phase_map: IssueContext.state_phase_map(issue, %{}),
      raw_state_by_route_key: raw_state_by_route_key,
      policy_by_route_key:
        IssueContext.policy_by_route_key(
          issue,
          ProfileRegistry.default_policy_by_route_key(profile_context.module, profile_context.options)
        )
    }
  end

  defp global_route_context(settings) do
    profile_context = ProfileRegistry.resolve!(settings.workflow.profile)

    %{
      profile_context: profile_context,
      state_phase_map: TrackerConfig.state_phase_map(settings.tracker) || %{},
      raw_state_by_route_key: global_raw_state_by_route_key(settings.tracker, profile_context),
      policy_by_route_key: global_policy_by_route_key(settings.tracker, profile_context)
    }
  end

  defp configured_raw_state_route_maps(settings) do
    profile_context = ProfileRegistry.resolve!(settings.workflow.profile)
    tracker = settings.tracker
    global_map = global_raw_state_by_route_key(tracker, profile_context)
    workflows_by_type = tracker |> TrackerConfig.lifecycle() |> map_value("workflows_by_type")

    workflow_maps =
      case workflows_by_type do
        workflows when is_map(workflows) ->
          workflows
          |> Map.values()
          |> Enum.map(&raw_state_by_route_key_from_workflow(&1, global_map, profile_context))

        _workflows ->
          []
      end

    [global_map | workflow_maps]
  end

  defp raw_state_by_route_key_from_workflow(workflow, base_map, profile_context) when is_map(workflow) do
    workflow
    |> map_value("raw_state_by_route_key")
    |> raw_state_by_route_key(base_map, profile_context)
  end

  defp raw_state_by_route_key_from_workflow(_workflow, base_map, _profile_context), do: base_map

  defp global_raw_state_by_route_key(tracker, profile_context) do
    tracker
    |> TrackerConfig.lifecycle()
    |> map_value("raw_state_by_route_key")
    |> raw_state_by_route_key(RoutePolicy.identity_raw_state_by_route_key(profile_context.module), profile_context)
  end

  defp raw_state_by_route_key(raw_state_by_route_key, base_map, %{module: profile_module})
       when is_map(base_map) do
    RoutePolicy.resolve_raw_state_by_route_key(raw_state_by_route_key, base_map, profile_module)
  end

  defp global_policy_by_route_key(tracker, profile_context) do
    default_policy_by_route_key =
      ProfileRegistry.default_policy_by_route_key(profile_context.module, profile_context.options)

    tracker
    |> TrackerConfig.lifecycle()
    |> map_value("policy_by_route_key")
    |> RoutePolicy.resolve_policy_by_route_key(
      default_policy_by_route_key,
      profile_context.module
    )
  end

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end
