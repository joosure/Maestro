defmodule SymphonyElixir.Workflow.Profiles.Triage do
  @moduledoc """
  Built-in issue triage workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.CapabilityNames, as: Capabilities
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [:intake, :classifying, :needs_info, :routed, :duplicate, :rejected]

  @default_policy_by_route_key %{
    intake: %{action: :transition_then_dispatch, transition_target: :classifying},
    classifying: %{action: :dispatch},
    needs_info: %{action: :wait},
    routed: %{action: :stop},
    duplicate: %{action: :stop},
    rejected: %{action: :stop}
  }

  @lifecycle_phase_by_route_key %{
    intake: WorkflowLifecycle.todo(),
    classifying: WorkflowLifecycle.in_progress(),
    needs_info: WorkflowLifecycle.human_review(),
    routed: WorkflowLifecycle.done(),
    duplicate: WorkflowLifecycle.canceled(),
    rejected: WorkflowLifecycle.canceled()
  }

  @options_schema %{
    "routing_taxonomy" => %{type: :string_list, default: []},
    "allow_duplicate_route" => %{type: :boolean, default: true}
  }

  @completion_contract %{
    required_outputs: [
      "Item type or category identified.",
      "Priority or urgency signal recorded when available.",
      "Suggested owner, workflow, or queue recorded."
    ],
    allowed_completion_routes: ["needs_info", "routed", "duplicate", "rejected"],
    evidence_requirements: [
      "Duplicate or related work linked when relation capabilities are available.",
      "Routing rationale recorded for the operator and tracker audience."
    ],
    handoff_expectations: [
      "Tracker metadata, assignment, or comment captures the triage result.",
      "Issue is routed to the selected completion route."
    ]
  }

  @required_capabilities [
    Capabilities.tracker_issue_read(),
    Capabilities.tracker_issue_update(),
    Capabilities.tracker_comment_read(),
    Capabilities.tracker_comment_write(),
    Capabilities.tracker_state_update(),
    Capabilities.agent_turn_run()
  ]

  @optional_capabilities [
    Capabilities.tracker_relation_read(),
    Capabilities.tracker_relation_write(),
    Capabilities.tracker_issue_create(),
    Capabilities.tracker_comment_update()
  ]

  @impl true
  def kind, do: "triage"

  @impl true
  def version, do: 1

  @impl true
  def route_keys, do: @route_keys

  @impl true
  def default_policy_by_route_key, do: @default_policy_by_route_key

  @impl true
  def default_policy_by_route_key(_options), do: @default_policy_by_route_key

  @impl true
  def lifecycle_phase_by_route_key, do: @lifecycle_phase_by_route_key

  @impl true
  def completion_contract(_options), do: @completion_contract

  @impl true
  def allowed_execution_profiles, do: []

  @impl true
  def allowed_execution_profiles(_options), do: []

  @impl true
  def runtime_execution_profile_extensions_enabled?(_options), do: false

  @impl true
  def execution_profile_required_capabilities(_execution_profile, _options), do: []

  @impl true
  def options_schema, do: @options_schema

  @impl true
  def default_options, do: ProfileOptions.default_options(@options_schema)

  @impl true
  def validate_options(options) when is_map(options) do
    ProfileOptions.validate(kind(), options, @options_schema)
  end

  def validate_options(options), do: {:error, {:invalid_profile_options, kind(), options}}

  @impl true
  def required_capabilities(_options), do: @required_capabilities

  @impl true
  def optional_capabilities(_options), do: @optional_capabilities
end
