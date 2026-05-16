defmodule SymphonyElixir.WorkflowRuntimeStructsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.CompletionValidator
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.Profile.Config, as: ProfileConfig
  alias SymphonyElixir.Workflow.Profile.Defaults, as: ProfileDefaults
  alias SymphonyElixir.Workflow.Profile.Resolved, as: ResolvedProfile
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Profiles.CodingPrDelivery
  alias SymphonyElixir.Workflow.Readiness
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy.Policy

  test "profile config keeps external string-keyed shape while internal code uses structs" do
    options = %{"execution_profiles" => %{"allowed" => ["land", "ship"]}}

    config =
      ProfileConfig.new!(%{
        "kind" => "coding_pr_delivery",
        "version" => 1,
        "options" => options
      })

    assert %ProfileConfig{
             kind: "coding_pr_delivery",
             version: 1,
             options: ^options
           } = config

    assert ProfileConfig.to_map(config) == %{
             "kind" => "coding_pr_delivery",
             "version" => 1,
             "options" => options
           }
  end

  test "profile registry resolves to a struct and exposes option-derived defaults as a struct" do
    assert {:ok, %ResolvedProfile{} = resolved} =
             ProfileRegistry.resolve(%{
               "kind" => "coding_pr_delivery",
               "version" => 1,
               "options" => %{"execution_profiles" => %{"allowed" => ["land", "ship"]}}
             })

    assert resolved.kind == "coding_pr_delivery"
    assert resolved.module == CodingPrDelivery

    defaults = ProfileRegistry.defaults(resolved.module, resolved.options)

    assert %ProfileDefaults{} = defaults
    assert defaults.route_keys == CodingPrDelivery.route_keys()
    assert defaults.policy_by_route_key.merging == %{action: :dispatch, execution_profile: "land"}
    assert defaults.allowed_execution_profiles == ["land", "ship"]
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

  test "readiness facts expose approval gate for review route" do
    issue =
      issue_for_route("In Review", "human_review", %{
        review: "In Review"
      })

    facts = Readiness.facts(issue)

    assert facts["profile"]["kind"] == "coding_pr_delivery"
    assert facts["route"]["key"] == "review"
    assert facts["route"]["action"] == "wait"
    assert facts["gate"]["status"] == "waiting"
    assert facts["gate"]["gate"] == "approval"
    assert facts["gate"]["category"] == "human"
  end

  test "readiness facts expose merge gate and conditional land capabilities" do
    issue =
      issue_for_route("Merging", "merging", %{
        merging: "Merging"
      })

    facts = Readiness.facts(issue)

    assert facts["route"]["key"] == "merging"
    assert facts["route"]["action"] == "dispatch"
    assert facts["route"]["execution_profile"] == "land"
    assert facts["gate"]["status"] == "blocked"
    assert facts["gate"]["gate"] == "merge"
    assert "linked change proposal exists" in facts["gate"]["required_evidence"]
    assert "repo_provider.merge" in facts["capabilities"]["conditional"]
    assert "repo_provider.merge" in facts["capabilities"]["required"]
  end

  test "readiness facts open merge gate when required merge evidence is present" do
    issue =
      issue_for_route("Merging", "merging", %{
        merging: "Merging"
      })

    facts =
      Readiness.facts(issue,
        available_capabilities: merge_gate_capabilities(),
        evidence: merge_evidence()
      )

    assert facts["gate"]["status"] == "open"
    assert facts["gate"]["gate"] == "merge"
    assert facts["gate"]["required_evidence"] == []
    assert "checks.passing" in facts["gate"]["observed_evidence"]
  end

  test "readiness facts fail closed on missing required capabilities when evidence is supplied" do
    issue =
      issue_for_route("In Progress", "in_progress", %{
        developing: "In Progress"
      })

    facts = Readiness.facts(issue, available_capabilities: [])

    assert facts["capabilities"]["checked"] == true
    assert "tracker.issue.read" in facts["capabilities"]["missing"]
    assert facts["gate"]["status"] == "blocked"
    assert facts["gate"]["gate"] == "capability"
  end

  test "completion validator accepts coding PR delivery evidence when contract checks pass" do
    issue =
      issue_for_route("In Review", "human_review", %{
        review: "In Review"
      })

    result =
      CompletionValidator.validate(issue,
        target_route: "review",
        evidence: merge_evidence()
      )

    assert result["status"] == "passed"
    assert result["route"] == "review"
    assert result["missing_evidence"] == []
    assert Enum.all?(result["checks"], &(Map.get(&1, "status") == "passed"))
  end

  test "completion validator reports failed evidence and disallowed completion routes" do
    issue =
      issue_for_route("In Progress", "in_progress", %{
        developing: "In Progress"
      })

    result =
      CompletionValidator.validate(issue,
        target_route: "developing",
        evidence: %{
          change_proposal: %{url: "https://github.example/acme/repo/pull/42"}
        }
      )

    assert result["status"] == "failed"
    assert "developing" == result["route"]
    assert "commit or diff evidence exists" in result["missing_evidence"]
    assert "current or target route is allowed by the completion contract" in result["missing_evidence"]
  end

  defp issue_for_route(state, lifecycle_phase, raw_state_overrides) do
    %Issue{
      state: state,
      lifecycle_phase: lifecycle_phase,
      workflow: %{
        profile: ProfileRegistry.default_profile_config(),
        raw_state_by_route_key:
          Map.merge(
            %{
              planning: "Todo",
              developing: "In Progress",
              review: "In Review",
              merging: "Merging",
              rework: "Rework",
              resolved: "Done",
              rejected: "Closed"
            },
            raw_state_overrides
          ),
        policy_by_route_key: CodingPrDelivery.default_policy_by_route_key()
      }
    }
  end

  defp merge_evidence do
    %{
      change_proposal: %{url: "https://github.example/acme/repo/pull/42", linked_issue: true},
      repo: %{commits: ["abc123"], diff_present: true},
      checks: %{read: true, status: "passing"},
      review: %{approved: true},
      tracker: %{workpad_written: true, state: "Merging"}
    }
  end

  defp merge_gate_capabilities do
    CodingPrDelivery.required_capabilities(ProfileRegistry.default_profile_config()["options"]) ++
      ["repo_provider.merge", "repo.merge_change_proposal"]
  end
end
