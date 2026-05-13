defmodule SymphonyElixir.Workflow.Profiles.ReviewRouting do
  @moduledoc """
  Built-in review routing workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

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

  @default_raw_state_by_route_key %{
    pending_review: "pending_review",
    routing: "routing",
    needs_context: "needs_context",
    assigned: "assigned",
    escalated: "escalated",
    completed: "completed",
    rejected: "rejected"
  }

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
    pending_review: "todo",
    routing: "in_progress",
    needs_context: "human_review",
    assigned: "done",
    escalated: "done",
    completed: "done",
    rejected: "canceled"
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

  @default_options %{
    "allowed_destinations" => [],
    "allow_escalation" => true
  }

  @required_capabilities [
    "tracker.issue.read",
    "tracker.issue.update",
    "tracker.comment.read",
    "tracker.comment.write",
    "tracker.state.update",
    "agent.turn.run"
  ]

  @optional_capabilities [
    "tracker.relation.read",
    "tracker.relation.write",
    "tracker.comment.update",
    "repo_provider.review.read"
  ]

  @impl true
  def kind, do: "review_routing"

  @impl true
  def version, do: 1

  @impl true
  def route_keys, do: @route_keys

  @impl true
  def default_raw_state_by_route_key, do: @default_raw_state_by_route_key

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
  def default_options, do: @default_options

  @impl true
  def validate_options(options) when is_map(options) do
    with :ok <- ProfileOptions.reject_unknown(kind(), options, Map.keys(@default_options)),
         :ok <- ProfileOptions.validate_string_list(kind(), options, @default_options, "allowed_destinations"),
         :ok <- ProfileOptions.validate_boolean(kind(), options, @default_options, "allow_escalation") do
      :ok
    end
  end

  def validate_options(options), do: {:error, {:invalid_profile_options, kind(), options}}

  @impl true
  def required_capabilities(_options), do: @required_capabilities

  @impl true
  def optional_capabilities(_options), do: @optional_capabilities
end
