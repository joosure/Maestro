defmodule SymphonyElixir.Workflow.Profiles.CodingPrDelivery do
  @moduledoc """
  Built-in coding and PR delivery workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.CapabilityNames, as: Capabilities
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.Profile.Options, as: ProfileOptions

  @kind "coding_pr_delivery"
  @review_route_key :review
  @rework_route_key :rework
  @route_keys [:planning, :developing, @review_route_key, :merging, @rework_route_key, :resolved, :rejected]
  @land_execution_profile "land"
  @default_allowed_execution_profiles [@land_execution_profile]
  @requirements_option_key "requirements"
  @change_proposal_option_key "change_proposal"
  @typed_tracker_tools_option_key "typed_tracker_tools"
  @typed_repo_tools_option_key "typed_repo_tools"
  @execution_profiles_option_key "execution_profiles"
  @allowed_execution_profiles_option_key "allowed"
  @readiness_option_key "readiness"
  @review_handoff_option_key "review_handoff"
  @change_proposal_checks_option_key "change_proposal_checks"
  @mode_option_key "mode"
  @change_proposal_checks_required_when_available "required_when_available"
  @change_proposal_checks_not_required "not_required"
  @change_proposal_checks_modes [
    @change_proposal_checks_required_when_available,
    @change_proposal_checks_not_required
  ]
  @routes_option_key "routes"
  @enabled_option_key "enabled"
  @configurable_route_keys [@rework_route_key]
  @enabled_route_option_schema %{type: {:map, %{@enabled_option_key => %{type: :boolean, default: true}}}}
  @route_options_schema Map.new(@configurable_route_keys, &{Atom.to_string(&1), @enabled_route_option_schema})
  @change_proposal_checks_options_schema %{
    @mode_option_key => %{
      type: {:enum, @change_proposal_checks_modes},
      default: @change_proposal_checks_required_when_available
    }
  }
  @review_handoff_options_schema %{
    @change_proposal_checks_option_key => %{type: {:map, @change_proposal_checks_options_schema}}
  }
  @readiness_options_schema %{
    @review_handoff_option_key => %{type: {:map, @review_handoff_options_schema}}
  }
  @default_completion_route_keys [@review_route_key, :merging, @rework_route_key, :resolved, :rejected]
  @tracker_handoff_expectation "Tracker comment or status surface records the result."

  @default_policy_by_route_key %{
    :planning => %{action: :transition_then_dispatch, transition_target: :developing},
    :developing => %{action: :dispatch},
    @review_route_key => %{action: :wait},
    :merging => %{action: :dispatch, execution_profile: @land_execution_profile},
    @rework_route_key => %{action: :dispatch},
    :resolved => %{action: :stop},
    :rejected => %{action: :stop}
  }

  @options_schema %{
    @requirements_option_key => %{
      type:
        {:map,
         %{
           @change_proposal_option_key => %{type: :boolean, default: true},
           @typed_tracker_tools_option_key => %{type: :boolean, default: false},
           @typed_repo_tools_option_key => %{type: :boolean, default: false}
         }}
    },
    @execution_profiles_option_key => %{
      type:
        {:map,
         %{
           @allowed_execution_profiles_option_key => %{
             type: {:name_list, min: 1, unique: true},
             default: @default_allowed_execution_profiles
           }
         }}
    },
    @readiness_option_key => %{
      type: {:map, @readiness_options_schema}
    },
    @routes_option_key => %{
      type: {:map, @route_options_schema}
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
    :planning => WorkflowLifecycle.todo(),
    :developing => WorkflowLifecycle.in_progress(),
    @review_route_key => WorkflowLifecycle.human_review(),
    :merging => WorkflowLifecycle.merging(),
    @rework_route_key => WorkflowLifecycle.rework(),
    :resolved => WorkflowLifecycle.done(),
    :rejected => WorkflowLifecycle.canceled()
  }

  @completion_contract_base %{
    required_outputs: [
      "Repository changes committed, or an explicit explanation that no code change is required.",
      "Validation evidence recorded.",
      "Blocking failures summarized for the operator and tracker audience."
    ],
    allowed_completion_routes: [],
    evidence_requirements: [
      "Test, check, or manual validation evidence when available.",
      "Change proposal or equivalent handoff link when required by profile options."
    ],
    handoff_expectations: []
  }

  @impl true
  def kind, do: @kind

  @spec review_route_key() :: atom()
  def review_route_key, do: @review_route_key

  @impl true
  def version, do: 1

  @impl true
  def route_keys, do: @route_keys

  @impl true
  def default_policy_by_route_key, do: @default_policy_by_route_key

  @impl true
  def default_policy_by_route_key(options) do
    Enum.reduce(@configurable_route_keys, @default_policy_by_route_key, fn route_key, policy_by_route_key ->
      maybe_disable_route(policy_by_route_key, route_key, route_enabled?(options, route_key))
    end)
  end

  @impl true
  def lifecycle_phase_by_route_key, do: @lifecycle_phase_by_route_key

  @impl true
  def completion_contract(options) do
    enabled_completion_route_keys = enabled_completion_route_keys(options)

    %{
      @completion_contract_base
      | allowed_completion_routes: Enum.map(enabled_completion_route_keys, &Atom.to_string/1),
        handoff_expectations: handoff_expectations(enabled_completion_route_keys)
    }
  end

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
        requirement_enabled?(options, @typed_repo_tools_option_key)
      )
    else
      []
    end
  end

  @impl true
  def options_schema, do: @options_schema

  @impl true
  def default_options, do: ProfileOptions.default_options(@options_schema)

  @impl true
  def validate_options(options) when is_map(options) do
    ProfileOptions.validate(kind(), options, @options_schema)
  end

  def validate_options(options), do: {:error, {:invalid_profile_options, kind(), options}}

  @spec change_proposal_required?(map()) :: boolean()
  def change_proposal_required?(options) when is_map(options),
    do: requirement_enabled?(options, @change_proposal_option_key)

  def change_proposal_required?(_options), do: true

  @spec review_handoff_change_proposal_checks_mode(map()) :: String.t()
  def review_handoff_change_proposal_checks_mode(options) when is_map(options) do
    default_options = default_options()
    default_readiness = Map.fetch!(default_options, @readiness_option_key)
    default_review_handoff = Map.fetch!(default_readiness, @review_handoff_option_key)
    default_change_proposal_checks = Map.fetch!(default_review_handoff, @change_proposal_checks_option_key)

    options
    |> option_map(@readiness_option_key, default_readiness)
    |> option_map(@review_handoff_option_key, default_review_handoff)
    |> option_map(@change_proposal_checks_option_key, default_change_proposal_checks)
    |> option_value(@mode_option_key, @change_proposal_checks_required_when_available)
  end

  def review_handoff_change_proposal_checks_mode(_options), do: @change_proposal_checks_required_when_available

  @spec review_handoff_change_proposal_checks_not_required?(map()) :: boolean()
  def review_handoff_change_proposal_checks_not_required?(options) when is_map(options),
    do: review_handoff_change_proposal_checks_mode(options) == @change_proposal_checks_not_required

  def review_handoff_change_proposal_checks_not_required?(_options), do: false

  @spec review_handoff_change_proposal_checks_required_when_available() :: String.t()
  def review_handoff_change_proposal_checks_required_when_available, do: @change_proposal_checks_required_when_available

  @spec review_handoff_change_proposal_checks_not_required() :: String.t()
  def review_handoff_change_proposal_checks_not_required, do: @change_proposal_checks_not_required

  @impl true
  def required_capabilities(options) when is_map(options) do
    require_change_proposal? = change_proposal_required?(options)
    require_typed_tracker_tools? = requirement_enabled?(options, @typed_tracker_tools_option_key)
    require_typed_repo_tools? = requirement_enabled?(options, @typed_repo_tools_option_key)

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

  defp requirement_enabled?(options, key) do
    requirements = Map.get(options, @requirements_option_key, %{})
    defaults = Map.fetch!(default_options(), @requirements_option_key)

    Map.get(requirements, key, Map.fetch!(defaults, key)) == true
  end

  defp allowed_execution_profile_names(options) do
    execution_profiles = Map.get(options, @execution_profiles_option_key, %{})
    defaults = Map.fetch!(default_options(), @execution_profiles_option_key)

    execution_profiles
    |> Map.get(@allowed_execution_profiles_option_key, Map.fetch!(defaults, @allowed_execution_profiles_option_key))
    |> Enum.uniq()
  end

  defp option_map(options, key, default) when is_map(options) and is_binary(key) and is_map(default) do
    case option_value(options, key, default) do
      value when is_map(value) -> value
      _value -> default
    end
  end

  defp option_value(options, key, default) when is_map(options) and is_binary(key) do
    Map.get(options, key, default)
  end

  defp maybe_disable_route(policy_by_route_key, _route_key, true), do: policy_by_route_key

  defp maybe_disable_route(policy_by_route_key, route_key, false) when is_atom(route_key) do
    Map.put(policy_by_route_key, route_key, %{action: :disabled})
  end

  defp enabled_completion_route_keys(options) do
    Enum.filter(@default_completion_route_keys, &route_enabled?(options, &1))
  end

  defp handoff_expectations(route_keys) when is_list(route_keys) do
    [
      "Handoff records one allowed completion route: #{route_keys |> Enum.map(&Atom.to_string/1) |> sentence_join()}.",
      @tracker_handoff_expectation
    ]
  end

  defp sentence_join([]), do: "No"
  defp sentence_join([label]), do: label
  defp sentence_join([left, right]), do: "#{left} or #{right}"

  defp sentence_join(labels) when is_list(labels) do
    {last, rest_reversed} = List.pop_at(Enum.reverse(labels), 0)

    rest_reversed
    |> Enum.reverse()
    |> Enum.join(", ")
    |> Kernel.<>(", or #{last}")
  end

  defp route_enabled?(options, route_key) when is_map(options) and is_atom(route_key) do
    defaults = default_options()
    routes = option_map(options, @routes_option_key, Map.fetch!(defaults, @routes_option_key))

    route_options =
      routes
      |> route_options(route_key)
      |> then(fn value -> if is_map(value), do: value, else: %{} end)

    option_value(route_options, @enabled_option_key, true) == true
  end

  defp route_enabled?(_options, _route_key), do: true

  defp route_options(routes, route_key) when is_map(routes) and is_atom(route_key) do
    Map.get(routes, Atom.to_string(route_key), %{})
  end

  defp route_options(_routes, _route_key), do: %{}
end
