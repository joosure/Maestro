defmodule SymphonyElixir.Workflow.Profiles.Triage do
  @moduledoc """
  Built-in issue triage workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [:intake, :classifying, :needs_info, :routed, :duplicate, :rejected]

  @default_raw_state_by_route_key %{
    intake: "intake",
    classifying: "classifying",
    needs_info: "needs_info",
    routed: "routed",
    duplicate: "duplicate",
    rejected: "rejected"
  }

  @default_policy_by_route_key %{
    intake: %{action: :transition_then_dispatch, transition_target: :classifying},
    classifying: %{action: :dispatch},
    needs_info: %{action: :wait},
    routed: %{action: :stop},
    duplicate: %{action: :stop},
    rejected: %{action: :stop}
  }

  @lifecycle_phase_by_route_key %{
    intake: "todo",
    classifying: "in_progress",
    needs_info: "human_review",
    routed: "done",
    duplicate: "canceled",
    rejected: "canceled"
  }

  @default_options %{
    "routing_taxonomy" => [],
    "allow_duplicate_route" => true
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
    "tracker.issue.create",
    "tracker.comment.update"
  ]

  @impl true
  def kind, do: "triage"

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
         :ok <- ProfileOptions.validate_string_list(kind(), options, @default_options, "routing_taxonomy"),
         :ok <- ProfileOptions.validate_boolean(kind(), options, @default_options, "allow_duplicate_route") do
      :ok
    end
  end

  def validate_options(options), do: {:error, {:invalid_profile_options, kind(), options}}

  @impl true
  def required_capabilities(_options), do: @required_capabilities

  @impl true
  def optional_capabilities(_options), do: @optional_capabilities
end
