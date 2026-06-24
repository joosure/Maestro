defmodule SymphonyElixir.Workflow.Profiles.RequirementRefinement do
  @moduledoc """
  Built-in requirement refinement workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Agent.Capabilities, as: AgentCapabilities
  alias SymphonyElixir.Repo.Capabilities, as: RepoCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [:draft, :refining, :needs_decision, :review, :ready, :rejected]

  @default_policy_by_route_key %{
    draft: %{action: :transition_then_dispatch, transition_target: :refining},
    refining: %{action: :dispatch},
    needs_decision: %{action: :wait},
    review: %{action: :wait},
    ready: %{action: :stop},
    rejected: %{action: :stop}
  }

  @lifecycle_phase_by_route_key %{
    draft: WorkflowLifecycle.todo(),
    refining: WorkflowLifecycle.in_progress(),
    needs_decision: WorkflowLifecycle.human_review(),
    review: WorkflowLifecycle.human_review(),
    ready: WorkflowLifecycle.done(),
    rejected: WorkflowLifecycle.canceled()
  }

  @completion_contract %{
    required_outputs: [
      "Problem statement rewritten or confirmed.",
      "Goals and non-goals made explicit.",
      "Dependencies, risks, and open decisions listed."
    ],
    allowed_completion_routes: ["needs_decision", "review", "ready", "rejected"],
    evidence_requirements: [
      "Testable acceptance criteria when required by profile options.",
      "Explicit non-goals or explanation when non-goals are required by profile options."
    ],
    handoff_expectations: [
      "Tracker issue fields or comments contain the refined requirement.",
      "Issue is routed to the selected completion route."
    ]
  }

  @options_schema %{
    "require_acceptance_criteria" => %{type: :boolean, default: true},
    "require_non_goals" => %{type: :boolean, default: true}
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
    TrackerCapabilities.comment_update(),
    TrackerCapabilities.relation_read(),
    TrackerCapabilities.relation_write(),
    RepoCapabilities.diff()
  ]

  @impl true
  def kind, do: "requirement_refinement"

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
