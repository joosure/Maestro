defmodule SymphonyElixir.WorkflowRoutePolicyTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.Profile.Config, as: ProfileConfig
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy, as: WorkflowRoutePolicy

  alias SymphonyElixir.Workflow.Profiles.{
    CodingPrDelivery,
    RequirementAnalysis,
    RequirementRefinement,
    ReviewRouting,
    Triage
  }

  test "normalize_action accepts the canonical action vocabulary" do
    assert WorkflowRoutePolicy.normalize_action("dispatch") == :dispatch
    assert WorkflowRoutePolicy.normalize_action("WAIT") == :wait
    assert WorkflowRoutePolicy.normalize_action("transition-then-dispatch") == :transition_then_dispatch
    assert WorkflowRoutePolicy.normalize_action(:stop) == :stop
    assert WorkflowRoutePolicy.normalize_action("disabled") == :disabled
    assert WorkflowRoutePolicy.normalize_action("unknown") == nil

    for action_name <- ["dispatch", "wait", "stop", "transition", "transition_then_dispatch", "disabled"] do
      assert action_name |> WorkflowRoutePolicy.normalize_action() |> WorkflowRoutePolicy.valid_action?()
    end

    assert WorkflowRoutePolicy.valid_action?(:disabled)
    refute WorkflowRoutePolicy.valid_action?("disabled")
  end

  test "route keys and lifecycle phase expectations are explicit profile vocabulary" do
    assert WorkflowRoutePolicy.route_key?("planning")
    refute WorkflowRoutePolicy.route_key?("status_4")
    assert WorkflowRoutePolicy.expected_lifecycle_phase("review") == WorkflowLifecycle.human_review()
    assert WorkflowRoutePolicy.expected_lifecycle_phase("status_4") == nil
  end

  test "profile registry exposes built-in workflow profiles" do
    assert {:ok, CodingPrDelivery} = ProfileRegistry.fetch("coding_pr_delivery", 1)
    assert {:ok, RequirementAnalysis} = ProfileRegistry.fetch("requirement_analysis", 1)
    assert {:ok, RequirementRefinement} = ProfileRegistry.fetch("requirement_refinement", 1)
    assert {:ok, ReviewRouting} = ProfileRegistry.fetch("review_routing", 1)
    assert {:ok, Triage} = ProfileRegistry.fetch("triage", 1)
    assert ProfileRegistry.default_profile_module().kind() == "coding_pr_delivery"
  end

  test "profile registry uses explicit per-kind default versions" do
    assert {:ok, 1} == ProfileRegistry.default_version("coding_pr_delivery")
    assert {:ok, 1} == ProfileRegistry.default_version("triage")
    assert {:error, {:unsupported_workflow_profile_kind, "missing"}} == ProfileRegistry.default_version("missing")

    assert %{"kind" => "triage", "version" => 1} =
             ProfileRegistry.normalize_config(%{"kind" => "triage"})

    assert {:error, {:unsupported_workflow_profile, "coding_pr_delivery", 2}} =
             ProfileRegistry.resolve(%{"kind" => "coding_pr_delivery", "version" => 2})
  end

  test "profile registry exposes strict resolved config boundary" do
    assert {:ok, %ProfileConfig{kind: "triage", version: 1, options: %{}}} =
             ProfileRegistry.resolve_config(%{kind: :triage})

    assert {:error, {:invalid_workflow_profile_config, "bad"}} =
             ProfileRegistry.resolve("bad")

    assert {:error, {:invalid_workflow_profile_kind, false}} =
             ProfileRegistry.resolve(%{"kind" => false})

    assert {:error, {:invalid_workflow_profile_options, "bad"}} =
             ProfileRegistry.resolve(%{"options" => "bad"})
  end

  test "profile registry resolves options and option-derived defaults" do
    assert {:ok, resolved_profile} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"execution_profiles" => %{"allowed" => ["land", "ship"]}}
             })

    assert resolved_profile.module == CodingPrDelivery
    assert resolved_profile.options["execution_profiles"]["allowed"] == ["land", "ship"]

    assert ProfileRegistry.default_policy_by_route_key(CodingPrDelivery, resolved_profile.options).merging ==
             %{action: :dispatch, execution_profile: "land"}

    assert ProfileRegistry.allowed_execution_profiles(CodingPrDelivery, resolved_profile.options) == ["land", "ship"]

    assert {:ok, no_rework_profile} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"routes" => %{"rework" => %{"enabled" => false}}}
             })

    assert no_rework_profile.options["routes"]["rework"]["enabled"] == false

    assert ProfileRegistry.default_policy_by_route_key(CodingPrDelivery, no_rework_profile.options).rework ==
             %{action: :disabled}

    refute "rework" in ProfileRegistry.completion_contract(CodingPrDelivery, no_rework_profile.options).allowed_completion_routes

    assert {:error, {:unknown_profile_option, "coding_pr_delivery", "unknown"}} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"unknown" => true}
             })

    assert {:error, {:unknown_profile_option, "coding_pr_delivery", "land_execution_profile"}} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"land_execution_profile" => "ship"}
             })

    assert {:error, {:unknown_profile_option, "coding_pr_delivery", "merging_route_execution_profile"}} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"merging_route_execution_profile" => "ship"}
             })

    assert {:error, {:invalid_profile_option, "coding_pr_delivery", "routes.rework.enabled", "false"}} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"routes" => %{"rework" => %{"enabled" => "false"}}}
             })

    assert {:error, {:unknown_profile_option, "coding_pr_delivery", "routes.developing"}} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"routes" => %{"developing" => %{"enabled" => false}}}
             })

    assert {:error, {:invalid_workflow_profile, "coding_pr_delivery", 0}} =
             ProfileRegistry.resolve(%{"kind" => "coding_pr_delivery", "version" => 0})
  end

  test "built-in workflow profiles expose internally consistent route contracts" do
    for profile_module <- ProfileRegistry.profiles() do
      route_keys = profile_module.route_keys()

      assert Map.keys(profile_module.default_policy_by_route_key()) |> Enum.sort() ==
               Enum.sort(route_keys)

      assert Map.keys(profile_module.lifecycle_phase_by_route_key()) |> Enum.sort() ==
               Enum.sort(route_keys)

      assert Enum.all?(profile_module.lifecycle_phase_by_route_key(), fn {_route_key, phase} ->
               WorkflowLifecycle.valid_phase?(phase)
             end)

      completion_contract = ProfileRegistry.completion_contract(profile_module, profile_module.default_options())

      assert is_map(completion_contract)
      assert Enum.all?(completion_contract.required_outputs, &is_binary/1)
      assert Enum.all?(completion_contract.evidence_requirements, &is_binary/1)
      assert Enum.all?(completion_contract.handoff_expectations, &is_binary/1)

      for route_key <- completion_contract.allowed_completion_routes do
        assert WorkflowRoutePolicy.route_key?(route_key, profile_module)
      end

      for {_route_key, %{transition_target: transition_target}} <-
            profile_module.default_policy_by_route_key() do
        assert transition_target in route_keys
      end
    end
  end

  test "resolve_policy_by_route_key preserves defaults while merging route-specific overrides" do
    resolved =
      WorkflowRoutePolicy.resolve_policy_by_route_key(%{
        "planning" => %{"transition_target" => "review"},
        "review" => %{"action" => "stop"},
        "merging" => %{"execution_profile" => "ship"},
        "rework" => %{"action" => "transition", "transition_target" => "review"}
      })

    assert resolved.planning == %{action: :transition_then_dispatch, transition_target: :review}
    assert resolved.review == %{action: :stop}
    assert resolved.merging == %{action: :dispatch, execution_profile: "ship"}
    assert resolved.rework == %{action: :transition, transition_target: :review}
    assert resolved.developing == %{action: :dispatch}
    assert resolved.resolved == %{action: :stop}
  end

  test "resolve_policy_by_route_key accepts profile-owned transition targets" do
    resolved =
      WorkflowRoutePolicy.resolve_policy_by_route_key(
        %{"intake" => %{"transition_target" => "analyzing"}},
        RequirementAnalysis.default_policy_by_route_key(),
        RequirementAnalysis
      )

    assert resolved.intake == %{action: :transition_then_dispatch, transition_target: :analyzing}
  end

  test "runtime policy lookup expects canonical atom route keys" do
    raw_policy_by_route_key = %{"rework" => %{"action" => "disabled"}}
    effective_policy_by_route_key = WorkflowRoutePolicy.resolve_policy_by_route_key(raw_policy_by_route_key)

    assert WorkflowRoutePolicy.policy_for_route_key(raw_policy_by_route_key, :rework) == %{}
    refute WorkflowRoutePolicy.disabled_route?(raw_policy_by_route_key, :rework)

    assert WorkflowRoutePolicy.policy_for_route_key(effective_policy_by_route_key, :rework) == %{action: :disabled}
    assert WorkflowRoutePolicy.disabled_route?(effective_policy_by_route_key, :rework)
  end

  test "raw policy resolver does not treat atom route keys as raw config" do
    base_policy_by_route_key = CodingPrDelivery.default_policy_by_route_key()

    resolved =
      WorkflowRoutePolicy.resolve_policy_by_route_key(
        %{rework: %{"action" => "disabled"}},
        base_policy_by_route_key,
        CodingPrDelivery
      )

    assert resolved.rework == base_policy_by_route_key.rework
  end

  test "raw policy resolver does not treat atom fields as raw config" do
    base_policy_by_route_key = CodingPrDelivery.default_policy_by_route_key()

    resolved =
      WorkflowRoutePolicy.resolve_policy_by_route_key(
        %{"rework" => %{action: :disabled}},
        base_policy_by_route_key,
        CodingPrDelivery
      )

    assert resolved.rework == base_policy_by_route_key.rework
  end

  test "effective policy overlays use atom route keys without parsing raw config" do
    base_policy_by_route_key = CodingPrDelivery.default_policy_by_route_key()

    raw_policy_by_route_key = %{"merging" => %{"action" => "wait"}}
    effective_policy_by_route_key = %{merging: %{action: :wait}}

    assert WorkflowRoutePolicy.merge_effective_policy_by_route_key(
             raw_policy_by_route_key,
             base_policy_by_route_key,
             CodingPrDelivery
           ).merging == base_policy_by_route_key.merging

    assert WorkflowRoutePolicy.merge_effective_policy_by_route_key(
             effective_policy_by_route_key,
             base_policy_by_route_key,
             CodingPrDelivery
           ).merging == %{action: :wait}
  end

  test "route_key_for_raw_state matches normalized raw tracker states" do
    raw_state_by_route_key = %{
      :developing => "Developing",
      planning: " Status_4 ",
      review: "QA_Review"
    }

    assert WorkflowRoutePolicy.route_key_for_raw_state("status_4", raw_state_by_route_key) == :planning
    assert WorkflowRoutePolicy.route_key_for_raw_state(" DEVELOPING ", raw_state_by_route_key) == :developing
    assert WorkflowRoutePolicy.route_key_for_raw_state("qa_review", raw_state_by_route_key) == :review
    assert WorkflowRoutePolicy.route_key_for_raw_state("missing", raw_state_by_route_key) == nil
  end

  test "raw_state resolves raw states from canonical atom-keyed effective maps" do
    raw_state_by_route_key = %{
      :planning => " queued ",
      review: "qa_review"
    }

    assert WorkflowRoutePolicy.raw_state_for_route_key(raw_state_by_route_key, :planning) == "queued"
    assert WorkflowRoutePolicy.raw_state_for_route_key(raw_state_by_route_key, :review) == "qa_review"
    assert WorkflowRoutePolicy.raw_state_for_route_key(raw_state_by_route_key, :resolved) == nil
    assert WorkflowRoutePolicy.raw_state_for_route_key(%{"review" => "qa_review"}, :review) == nil
  end

  test "raw-state config resolver normalizes string-keyed raw route maps" do
    raw_state_by_route_key = %{
      "planning" => " queued ",
      "review" => "qa_review"
    }

    resolved =
      WorkflowRoutePolicy.resolve_raw_state_by_route_key(
        raw_state_by_route_key,
        %{planning: "Planning", review: "Review"},
        CodingPrDelivery
      )

    assert resolved.planning == "queued"
    assert resolved.review == "qa_review"
  end

  test "raw-state config resolver does not treat atom route keys as raw config" do
    base_raw_state_by_route_key = %{planning: "Planning", review: "Review"}

    resolved =
      WorkflowRoutePolicy.resolve_raw_state_by_route_key(
        %{review: "qa_review"},
        base_raw_state_by_route_key,
        CodingPrDelivery
      )

    assert resolved.review == "Review"
  end

  test "disabled route policies remove raw tracker states from effective route maps" do
    raw_state_by_route_key = %{
      :planning => "Todo",
      :rework => "Rework",
      review: "In Review"
    }

    policy_by_route_key =
      WorkflowRoutePolicy.resolve_policy_by_route_key(
        %{"rework" => %{"action" => "disabled"}},
        CodingPrDelivery.default_policy_by_route_key(),
        CodingPrDelivery
      )

    assert WorkflowRoutePolicy.remove_disabled_raw_states(raw_state_by_route_key, policy_by_route_key, CodingPrDelivery) ==
             %{
               :planning => "Todo",
               review: "In Review"
             }
  end
end
