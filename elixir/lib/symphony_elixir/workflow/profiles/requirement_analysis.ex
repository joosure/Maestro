defmodule SymphonyElixir.Workflow.Profiles.RequirementAnalysis do
  @moduledoc """
  Built-in requirement analysis workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.CapabilityNames, as: Capabilities
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [:intake, :analyzing, :needs_info, :review, :ready, :rejected]

  @default_policy_by_route_key %{
    intake: %{action: :transition_then_dispatch, transition_target: :analyzing},
    analyzing: %{action: :dispatch},
    needs_info: %{action: :wait},
    review: %{action: :wait},
    ready: %{action: :stop},
    rejected: %{action: :stop}
  }

  @lifecycle_phase_by_route_key %{
    intake: WorkflowLifecycle.todo(),
    analyzing: WorkflowLifecycle.in_progress(),
    needs_info: WorkflowLifecycle.human_review(),
    review: WorkflowLifecycle.human_review(),
    ready: WorkflowLifecycle.done(),
    rejected: WorkflowLifecycle.canceled()
  }

  @completion_contract %{
    required_outputs: [
      "Ambiguity list created or refreshed.",
      "Assumptions clearly separated from facts.",
      "Blocking and non-blocking open questions classified."
    ],
    allowed_completion_routes: ["needs_info", "review", "ready", "rejected"],
    evidence_requirements: [
      "Acceptance criteria drafted when enough information exists.",
      "References to source comments, issue fields, or external facts when present."
    ],
    handoff_expectations: [
      "Analysis summary is recorded for the tracker audience.",
      "Issue is routed to needs_info, review, ready, or rejected."
    ]
  }

  @question_policy_values ["blocking_only", "blocking_and_non_blocking"]

  @options_schema %{
    "require_acceptance_criteria" => %{type: :boolean, default: false},
    "question_policy" => %{type: {:enum, @question_policy_values}, default: "blocking_and_non_blocking"}
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
    Capabilities.tracker_comment_update(),
    Capabilities.tracker_relation_read(),
    Capabilities.tracker_relation_write()
  ]

  @impl true
  def kind, do: "requirement_analysis"

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
