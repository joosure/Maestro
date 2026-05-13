defmodule SymphonyElixir.Workflow.Profiles.CodingPrDelivery do
  @moduledoc """
  Built-in coding and PR delivery workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [:planning, :developing, :review, :merging, :rework, :resolved, :rejected]

  @default_raw_state_by_route_key %{
    planning: "planning",
    developing: "developing",
    review: "review",
    merging: "merging",
    rework: "rework",
    resolved: "resolved",
    rejected: "rejected"
  }

  @default_policy_by_route_key %{
    planning: %{action: :transition_then_dispatch, transition_target: :developing},
    developing: %{action: :dispatch},
    review: %{action: :wait},
    merging: %{action: :dispatch, execution_profile: "land"},
    rework: %{action: :dispatch},
    resolved: %{action: :stop},
    rejected: %{action: :stop}
  }

  @default_options %{
    "require_change_proposal" => true,
    "require_typed_tracker_tools" => false,
    "require_typed_repo_tools" => false,
    "land_execution_profile" => "land"
  }

  @required_capabilities [
    "tracker.issue.read",
    "tracker.comment.read",
    "tracker.comment.write",
    "tracker.state.update",
    "repo.checkout",
    "repo.diff",
    "repo.commit",
    "repo.push",
    "agent.turn.run"
  ]

  @change_proposal_capabilities [
    "repo_provider.change_proposal.create",
    "repo_provider.change_proposal.read",
    "repo_provider.review.read",
    "repo_provider.check.read"
  ]

  @typed_tracker_capabilities [
    "tracker.issue_snapshot",
    "tracker.move_issue",
    "tracker.upsert_workpad"
  ]

  @typed_change_proposal_capabilities [
    "tracker.attach_change_proposal"
  ]

  @typed_repo_capabilities [
    "repo.change_proposal_snapshot",
    "repo.create_or_update_change_proposal",
    "repo.read_change_proposal_discussion",
    "repo.add_change_proposal_comment",
    "repo.reply_change_proposal_review_comment",
    "repo.read_change_proposal_checks"
  ]

  @typed_repo_land_capabilities [
    "repo.merge_change_proposal"
  ]

  @land_execution_profile_capabilities [
    "repo_provider.merge"
  ]

  @optional_capabilities (@change_proposal_capabilities ++
                            @typed_repo_capabilities ++
                            @typed_repo_land_capabilities ++
                            [
                              @land_execution_profile_capabilities,
                              "repo_provider.review.write",
                              "tracker.relation.read",
                              "tracker.relation.write",
                              "tracker.upsert_comment",
                              "tracker.create_follow_up_issue",
                              "tracker.read_issue_relations",
                              "tracker.add_issue_relation",
                              "tracker.read_issue_dependencies",
                              "tracker.save_issue_dependency",
                              "repo.submit_change_proposal_review"
                            ])
                         |> List.flatten()

  @lifecycle_phase_by_route_key %{
    planning: "todo",
    developing: "in_progress",
    review: "human_review",
    merging: "merging",
    rework: "rework",
    resolved: "done",
    rejected: "canceled"
  }

  @completion_contract %{
    required_outputs: [
      "Repository changes committed, or an explicit explanation that no code change is required.",
      "Validation evidence recorded.",
      "Blocking failures summarized for the operator and tracker audience."
    ],
    allowed_completion_routes: ["review", "merging", "rework", "resolved", "rejected"],
    evidence_requirements: [
      "Test, check, or manual validation evidence when available.",
      "Change proposal or equivalent handoff link when required by profile options."
    ],
    handoff_expectations: [
      "Review, merge, rework, resolved, or rejected handoff state is reached.",
      "Tracker comment or status surface records the result."
    ]
  }

  @impl true
  def kind, do: "coding_pr_delivery"

  @impl true
  def version, do: 1

  @impl true
  def route_keys, do: @route_keys

  @impl true
  def default_raw_state_by_route_key, do: @default_raw_state_by_route_key

  @impl true
  def default_policy_by_route_key, do: @default_policy_by_route_key

  @impl true
  def default_policy_by_route_key(options) when is_map(options) do
    execution_profile = land_execution_profile(options)

    put_in(@default_policy_by_route_key, [:merging, :execution_profile], execution_profile)
  end

  @impl true
  def lifecycle_phase_by_route_key, do: @lifecycle_phase_by_route_key

  @impl true
  def completion_contract(_options), do: @completion_contract

  @impl true
  def allowed_execution_profiles, do: ["land"]

  @impl true
  def allowed_execution_profiles(options) when is_map(options),
    do: [land_execution_profile(options)]

  @impl true
  def runtime_execution_profile_extensions_enabled?(_options), do: true

  @impl true
  def execution_profile_required_capabilities(execution_profile, options)
      when is_binary(execution_profile) and is_map(options) do
    if execution_profile == land_execution_profile(options) do
      @land_execution_profile_capabilities
      |> maybe_add_capabilities(
        @typed_repo_land_capabilities,
        option_enabled?(options, "require_typed_repo_tools")
      )
    else
      []
    end
  end

  @impl true
  def default_options, do: @default_options

  @impl true
  def validate_options(options) when is_map(options) do
    with :ok <- ProfileOptions.reject_unknown(kind(), options, Map.keys(@default_options)),
         :ok <-
           ProfileOptions.validate_boolean(
             kind(),
             options,
             @default_options,
             "require_change_proposal"
           ),
         :ok <-
           ProfileOptions.validate_boolean(
             kind(),
             options,
             @default_options,
             "require_typed_tracker_tools"
           ),
         :ok <-
           ProfileOptions.validate_boolean(
             kind(),
             options,
             @default_options,
             "require_typed_repo_tools"
           ),
         :ok <-
           ProfileOptions.validate_name(
             kind(),
             options,
             @default_options,
             "land_execution_profile"
           ) do
      :ok
    end
  end

  def validate_options(options), do: {:error, {:invalid_profile_options, kind(), options}}

  @impl true
  def required_capabilities(options) when is_map(options) do
    require_change_proposal? = option_enabled?(options, "require_change_proposal")
    require_typed_tracker_tools? = option_enabled?(options, "require_typed_tracker_tools")
    require_typed_repo_tools? = option_enabled?(options, "require_typed_repo_tools")

    @required_capabilities
    |> maybe_add_capabilities(@change_proposal_capabilities, require_change_proposal?)
    |> maybe_add_capabilities(@typed_tracker_capabilities, require_typed_tracker_tools?)
    |> maybe_add_capabilities(
      @typed_repo_capabilities,
      require_typed_repo_tools? and require_change_proposal?
    )
    |> maybe_add_capabilities(
      @typed_change_proposal_capabilities,
      require_typed_tracker_tools? and require_change_proposal?
    )
  end

  @impl true
  def optional_capabilities(_options), do: @optional_capabilities

  defp maybe_add_capabilities(capabilities, additional_capabilities, true),
    do: capabilities ++ additional_capabilities

  defp maybe_add_capabilities(capabilities, _additional_capabilities, false), do: capabilities

  defp option_enabled?(options, key) do
    Map.get(options, key, @default_options[key]) == true
  end

  defp land_execution_profile(options) do
    ProfileOptions.value(options, @default_options, "land_execution_profile")
  end
end
