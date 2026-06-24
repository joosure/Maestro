defmodule SymphonyElixir.Workflow.Profiles.ReviewRouting do
  @moduledoc """
  Built-in review routing workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Agent.Capabilities, as: AgentCapabilities
  alias SymphonyElixir.RepoProvider.Capabilities, as: RepoProviderCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [
    :pending_review,
    :routing,
    :needs_context,
    :assigned,
    :escalated,
    :completed,
    :rejected
  ]

  @default_policy_by_route_key %{
    pending_review: %{action: :transition_then_dispatch, transition_target: :routing},
    routing: %{action: :dispatch},
    needs_context: %{action: :wait},
    assigned: %{action: :stop},
    escalated: %{action: :stop},
    completed: %{action: :stop},
    rejected: %{action: :stop}
  }

  @lifecycle_phase_by_route_key %{
    pending_review: WorkflowLifecycle.todo(),
    routing: WorkflowLifecycle.in_progress(),
    needs_context: WorkflowLifecycle.human_review(),
    assigned: WorkflowLifecycle.done(),
    escalated: WorkflowLifecycle.done(),
    completed: WorkflowLifecycle.done(),
    rejected: WorkflowLifecycle.canceled()
  }

  @completion_contract %{
    required_outputs: [
      "Routing rationale recorded.",
      "Next reviewer, team, or queue selected when enough context exists.",
      "Missing context listed when assignment is blocked."
    ],
    allowed_completion_routes: ["needs_context", "assigned", "escalated", "completed", "rejected"],
    evidence_requirements: [
      "Escalation reason recorded when escalation is selected.",
      "References to review context or existing reviewers when available."
    ],
    handoff_expectations: [
      "Tracker handoff comment, assignment, or metadata update records the route.",
      "Issue is routed to the selected completion route."
    ]
  }

  @options_schema %{
    "allowed_destinations" => %{type: :string_list, default: []},
    "allow_escalation" => %{type: :boolean, default: true}
  }

  @required_capabilities [
    TrackerCapabilities.issue_read(),
    TrackerCapabilities.issue_update(),
    TrackerCapabilities.comment_read(),
    TrackerCapabilities.comment_write(),
    TrackerCapabilities.state_update(),
    AgentCapabilities.turn_run()
  ]

  @optional_capabilities [
    TrackerCapabilities.relation_read(),
    TrackerCapabilities.relation_write(),
    TrackerCapabilities.comment_update(),
    RepoProviderCapabilities.review_read()
  ]

  @impl true
  def kind, do: "review_routing"

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
