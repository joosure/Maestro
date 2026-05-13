defmodule SymphonyElixir.WorkflowRuntimeStructsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.Profile.Config, as: ProfileConfig
  alias SymphonyElixir.Workflow.Profile.Defaults, as: ProfileDefaults
  alias SymphonyElixir.Workflow.Profile.Resolved, as: ResolvedProfile
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Profiles.CodingPrDelivery
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy.Policy

  test "profile config keeps external string-keyed shape while internal code uses structs" do
    config =
      ProfileConfig.new!(%{
        "kind" => "coding_pr_delivery",
        "version" => 1,
        "options" => %{"land_execution_profile" => "ship"}
      })

    assert %ProfileConfig{
             kind: "coding_pr_delivery",
             version: 1,
             options: %{"land_execution_profile" => "ship"}
           } = config

    assert ProfileConfig.to_map(config) == %{
             "kind" => "coding_pr_delivery",
             "version" => 1,
             "options" => %{"land_execution_profile" => "ship"}
           }
  end

  test "profile registry resolves to a struct and exposes option-derived defaults as a struct" do
    assert {:ok, %ResolvedProfile{} = resolved} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"land_execution_profile" => "ship"}
             })

    assert resolved.kind == "coding_pr_delivery"
    assert resolved.module == CodingPrDelivery

    defaults = ProfileRegistry.defaults(resolved.module, resolved.options)

    assert %ProfileDefaults{} = defaults
    assert defaults.route_keys == CodingPrDelivery.route_keys()
    assert defaults.policy_by_route_key.merging == %{action: :dispatch, execution_profile: "ship"}
  end

  test "route policy policy struct normalizes policy action and preserves map projection" do
    policy =
      Policy.new!(%{
        "action" => "transition-then-dispatch",
        "transition_target" => :developing
      })

    assert policy.action == :transition_then_dispatch
    assert Policy.to_map(policy) == %{action: :transition_then_dispatch, transition_target: :developing}
  end

  test "route facts resolve current issue route from workflow profile facts" do
    issue = %Issue{
      state: "status_1",
      lifecycle_phase: "todo",
      workflow: %{
        profile: ProfileRegistry.default_profile_config(),
        state_phase_map: %{"status_1" => "todo", "developing" => "coding"},
        raw_state_by_route_key: %{
          planning: "status_1",
          developing: "developing",
          review: "review",
          merging: "merging",
          rework: "rework",
          resolved: "resolved",
          rejected: "rejected"
        },
        policy_by_route_key: CodingPrDelivery.default_policy_by_route_key()
      }
    }

    assert %RouteFacts{} = facts = IssueContext.route_facts(issue)
    assert facts.route_key == :planning
    assert facts.raw_state == "status_1"
    assert facts.lifecycle_phase == "todo"
    assert facts.action == :transition_then_dispatch
    assert facts.transition_target == :developing
    assert RouteFacts.policy_map(facts) == %{action: :transition_then_dispatch, transition_target: :developing}
  end

  test "route facts can resolve from pure field input without issue coupling" do
    assert %RouteFacts{} =
             facts =
             RouteFacts.from_fields(%{
               state: "status_1",
               lifecycle_phase: nil,
               state_phase_map: %{"status_1" => "todo"},
               raw_state_by_route_key: %{planning: "status_1"},
               policy_by_route_key: %{planning: %{action: :wait}},
               profile_module: CodingPrDelivery
             })

    assert facts.route_key == :planning
    assert facts.lifecycle_phase == "todo"
    assert facts.action == :wait
  end
end
