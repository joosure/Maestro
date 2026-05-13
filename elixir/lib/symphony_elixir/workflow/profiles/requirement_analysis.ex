defmodule SymphonyElixir.Workflow.Profiles.RequirementAnalysis do
  @moduledoc """
  Built-in requirement analysis workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [:intake, :analyzing, :needs_info, :review, :ready, :rejected]

  @default_raw_state_by_route_key %{
    intake: "intake",
    analyzing: "analyzing",
    needs_info: "needs_info",
    review: "review",
    ready: "ready",
    rejected: "rejected"
  }

  @default_policy_by_route_key %{
    intake: %{action: :transition_then_dispatch, transition_target: :analyzing},
    analyzing: %{action: :dispatch},
    needs_info: %{action: :wait},
    review: %{action: :wait},
    ready: %{action: :stop},
    rejected: %{action: :stop}
  }

  @lifecycle_phase_by_route_key %{
    intake: "todo",
    analyzing: "in_progress",
    needs_info: "human_review",
    review: "human_review",
    ready: "done",
    rejected: "canceled"
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

  @default_options %{
    "require_acceptance_criteria" => false,
    "question_policy" => "blocking_and_non_blocking"
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
    "tracker.comment.update",
    "tracker.relation.read",
    "tracker.relation.write"
  ]

  @impl true
  def kind, do: "requirement_analysis"

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
         :ok <- ProfileOptions.validate_boolean(kind(), options, @default_options, "require_acceptance_criteria"),
         :ok <-
           ProfileOptions.validate_enum(
             kind(),
             options,
             @default_options,
             "question_policy",
             ["blocking_only", "blocking_and_non_blocking"]
           ) do
      :ok
    end
  end

  def validate_options(options), do: {:error, {:invalid_profile_options, kind(), options}}

  @impl true
  def required_capabilities(_options), do: @required_capabilities

  @impl true
  def optional_capabilities(_options), do: @optional_capabilities
end
