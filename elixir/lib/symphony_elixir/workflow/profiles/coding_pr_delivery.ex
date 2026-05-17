defmodule SymphonyElixir.Workflow.Profiles.CodingPrDelivery do
  @moduledoc """
  Built-in coding and PR delivery workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.CapabilityNames, as: Capabilities
  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @route_keys [:planning, :developing, :review, :merging, :rework, :resolved, :rejected]
  @land_execution_profile "land"
  @default_allowed_execution_profiles [@land_execution_profile]

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
    merging: %{action: :dispatch, execution_profile: @land_execution_profile},
    rework: %{action: :dispatch},
    resolved: %{action: :stop},
    rejected: %{action: :stop}
  }

  @default_options %{
    "requirements" => %{
      "change_proposal" => true,
      "typed_tracker_tools" => false,
      "typed_repo_tools" => false
    },
    "execution_profiles" => %{
      "allowed" => @default_allowed_execution_profiles
    }
  }

  @required_capabilities [
    Capabilities.tracker_issue_read(),
    Capabilities.tracker_comment_read(),
    Capabilities.tracker_comment_write(),
    Capabilities.tracker_state_update(),
    Capabilities.repo_checkout(),
    Capabilities.repo_diff(),
    Capabilities.repo_commit(),
    Capabilities.repo_push(),
    Capabilities.agent_turn_run()
  ]

  @change_proposal_capabilities [
    Capabilities.repo_provider_change_proposal_create(),
    Capabilities.repo_provider_change_proposal_read(),
    Capabilities.repo_provider_review_read(),
    Capabilities.repo_provider_check_read()
  ]

  @typed_tracker_capabilities [
    Capabilities.tracker_issue_snapshot(),
    Capabilities.tracker_move_issue(),
    Capabilities.tracker_upsert_workpad()
  ]

  @typed_change_proposal_capabilities [
    Capabilities.tracker_attach_change_proposal()
  ]

  @typed_repo_capabilities [
    Capabilities.repo_change_proposal_snapshot(),
    Capabilities.repo_create_or_update_change_proposal(),
    Capabilities.repo_read_change_proposal_discussion(),
    Capabilities.repo_add_change_proposal_comment(),
    Capabilities.repo_reply_change_proposal_review_comment(),
    Capabilities.repo_read_change_proposal_checks()
  ]

  @typed_repo_land_capabilities [
    Capabilities.repo_merge_change_proposal()
  ]

  @profile_owned_execution_profile_capabilities [
    Capabilities.repo_provider_merge()
  ]

  @optional_capabilities (@change_proposal_capabilities ++
                            @typed_repo_capabilities ++
                            @typed_repo_land_capabilities ++
                            [
                              @profile_owned_execution_profile_capabilities,
                              Capabilities.repo_provider_review_write(),
                              Capabilities.tracker_relation_read(),
                              Capabilities.tracker_relation_write(),
                              Capabilities.tracker_upsert_comment(),
                              Capabilities.tracker_create_follow_up_issue(),
                              Capabilities.tracker_read_issue_relations(),
                              Capabilities.tracker_add_issue_relation(),
                              Capabilities.tracker_read_issue_dependencies(),
                              Capabilities.tracker_save_issue_dependency(),
                              Capabilities.repo_submit_change_proposal_review()
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
  def default_policy_by_route_key(_options) do
    @default_policy_by_route_key
  end

  @impl true
  def lifecycle_phase_by_route_key, do: @lifecycle_phase_by_route_key

  @impl true
  def completion_contract(_options), do: @completion_contract

  @impl true
  def allowed_execution_profiles, do: @default_allowed_execution_profiles

  @impl true
  def allowed_execution_profiles(options) when is_map(options),
    do: allowed_execution_profile_names(options)

  @impl true
  def runtime_execution_profile_extensions_enabled?(_options), do: true

  @impl true
  def execution_profile_required_capabilities(execution_profile, options)
      when is_binary(execution_profile) and is_map(options) do
    if execution_profile == @land_execution_profile and execution_profile in allowed_execution_profile_names(options) do
      @profile_owned_execution_profile_capabilities
      |> maybe_add_capabilities(
        @typed_repo_land_capabilities,
        requirement_enabled?(options, "typed_repo_tools")
      )
    else
      []
    end
  end

  @impl true
  def default_options, do: @default_options

  @impl true
  def validate_options(options) when is_map(options) do
    with :ok <- validate_top_level_options(options),
         :ok <- validate_requirements(options),
         :ok <-
           validate_execution_profiles(options) do
      :ok
    end
  end

  def validate_options(options), do: {:error, {:invalid_profile_options, kind(), options}}

  @impl true
  def required_capabilities(options) when is_map(options) do
    require_change_proposal? = requirement_enabled?(options, "change_proposal")
    require_typed_tracker_tools? = requirement_enabled?(options, "typed_tracker_tools")
    require_typed_repo_tools? = requirement_enabled?(options, "typed_repo_tools")

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

  defp validate_top_level_options(options) when is_map(options) do
    ProfileOptions.reject_unknown(kind(), options, Map.keys(@default_options))
  end

  defp validate_requirements(options) when is_map(options) do
    with {:ok, requirements} <- option_group(options, "requirements"),
         :ok <-
           reject_unknown_nested_options(
             requirements,
             "requirements",
             Map.keys(@default_options["requirements"])
           ),
         :ok <- validate_boolean_requirement(requirements, "change_proposal"),
         :ok <- validate_boolean_requirement(requirements, "typed_tracker_tools"),
         :ok <- validate_boolean_requirement(requirements, "typed_repo_tools") do
      :ok
    end
  end

  defp validate_execution_profiles(options) when is_map(options) do
    with {:ok, execution_profiles} <- option_group(options, "execution_profiles"),
         :ok <- reject_unknown_nested_options(execution_profiles, "execution_profiles", ["allowed"]),
         :ok <- validate_allowed_execution_profiles(execution_profiles) do
      :ok
    end
  end

  defp option_group(options, key) when is_map(options) and is_binary(key) do
    case Map.get(options, key, Map.fetch!(@default_options, key)) do
      value when is_map(value) -> {:ok, value}
      value -> {:error, {:invalid_profile_option, kind(), key, value}}
    end
  end

  defp reject_unknown_nested_options(options, path, known_keys)
       when is_map(options) and is_binary(path) and is_list(known_keys) do
    case Map.keys(options) -- known_keys do
      [] -> :ok
      [unknown_key | _rest] -> {:error, {:unknown_profile_option, kind(), "#{path}.#{unknown_key}"}}
    end
  end

  defp validate_boolean_requirement(requirements, key) when is_map(requirements) and is_binary(key) do
    defaults = @default_options["requirements"]

    case Map.get(requirements, key, Map.fetch!(defaults, key)) do
      value when is_boolean(value) -> :ok
      value -> {:error, {:invalid_profile_option, kind(), "requirements.#{key}", value}}
    end
  end

  defp validate_allowed_execution_profiles(execution_profiles) when is_map(execution_profiles) do
    allowed = Map.get(execution_profiles, "allowed", @default_options["execution_profiles"]["allowed"])

    cond do
      not is_list(allowed) ->
        {:error, {:invalid_profile_option, kind(), "execution_profiles.allowed", allowed}}

      allowed == [] ->
        {:error, {:invalid_profile_option, kind(), "execution_profiles.allowed", allowed}}

      not Enum.all?(allowed, &valid_execution_profile_name?/1) ->
        {:error, {:invalid_profile_option, kind(), "execution_profiles.allowed", allowed}}

      Enum.uniq(allowed) != allowed ->
        {:error, {:invalid_profile_option, kind(), "execution_profiles.allowed", allowed}}

      true ->
        :ok
    end
  end

  defp valid_execution_profile_name?(value) when is_binary(value) do
    String.match?(value, ~r/^[a-z][a-z0-9_]*$/)
  end

  defp valid_execution_profile_name?(_value), do: false

  defp requirement_enabled?(options, key) do
    requirements = Map.get(options, "requirements", %{})
    defaults = @default_options["requirements"]

    Map.get(requirements, key, Map.fetch!(defaults, key)) == true
  end

  defp allowed_execution_profile_names(options) do
    execution_profiles = Map.get(options, "execution_profiles", %{})
    defaults = @default_options["execution_profiles"]

    execution_profiles
    |> Map.get("allowed", Map.fetch!(defaults, "allowed"))
    |> Enum.uniq()
  end
end
