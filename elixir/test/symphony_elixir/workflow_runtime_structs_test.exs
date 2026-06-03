defmodule SymphonyElixir.WorkflowRuntimeStructsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Capabilities
  alias SymphonyElixir.Workflow.CompletionValidator
  alias SymphonyElixir.Workflow.Effective
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

    assert {:ok, "coding_pr_delivery"} = ProfileConfig.fetch(config, :kind)
    assert :error = ProfileConfig.fetch(config, "kind")
    assert config[:kind] == "coding_pr_delivery"
    assert is_nil(config["kind"])

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

  test "coding PR delivery profile owns review handoff change-proposal-checks mode option" do
    defaults = CodingPrDelivery.default_options()

    assert CodingPrDelivery.review_handoff_change_proposal_checks_mode(defaults) ==
             CodingPrDelivery.review_handoff_change_proposal_checks_required_when_available()

    no_checks_options = %{
      "readiness" => %{
        "review_handoff" => %{
          "change_proposal_checks" => %{
            "mode" => CodingPrDelivery.review_handoff_change_proposal_checks_not_required()
          }
        }
      }
    }

    assert :ok = CodingPrDelivery.validate_options(no_checks_options)
    assert CodingPrDelivery.review_handoff_change_proposal_checks_not_required?(no_checks_options)

    assert {:error, {:invalid_profile_option, "coding_pr_delivery", "readiness.review_handoff.change_proposal_checks.mode", "best_effort"}} =
             CodingPrDelivery.validate_options(%{
               "readiness" => %{
                 "review_handoff" => %{
                   "change_proposal_checks" => %{
                     "mode" => "best_effort"
                   }
                 }
               }
             })
  end

  test "route policy policy struct preserves canonical effective map projection" do
    policy =
      Policy.new!(%{
        action: :transition_then_dispatch,
        transition_target: :developing
      })

    assert policy.action == :transition_then_dispatch
    assert {:ok, :transition_then_dispatch} = Policy.fetch(policy, :action)
    assert :error = Policy.fetch(policy, "action")
    assert policy[:action] == :transition_then_dispatch
    assert is_nil(policy["action"])
    assert Policy.to_map(policy) == %{action: :transition_then_dispatch, transition_target: :developing}

    assert_raise KeyError, fn -> Policy.new!(%{"action" => :dispatch}) end
    assert_raise ArgumentError, fn -> Policy.new!(%{action: "dispatch"}) end
  end

  test "effective workflow struct access uses canonical atom fields only" do
    workflow =
      Effective.new!(%{
        workitem_type_id: nil,
        active_states: ["Developing"],
        terminal_states: ["Done"],
        state_phase_map: %{"Developing" => "coding", "Done" => "done"},
        raw_state_by_route_key: %{developing: "Developing", resolved: "Done"},
        policy_by_route_key: %{developing: %{action: :dispatch}, resolved: %{action: :stop}},
        profile: ProfileRegistry.default_profile_config(),
        profile_kind: "coding_pr_delivery",
        profile_version: 1,
        profile_options: %{},
        allowed_execution_profiles: ["work"],
        completion_contract: %{},
        required_capabilities: [],
        optional_capabilities: []
      })

    assert {:ok, "coding_pr_delivery"} = Effective.fetch(workflow, :profile_kind)
    assert :error = Effective.fetch(workflow, "profile_kind")
    assert workflow[:profile_kind] == "coding_pr_delivery"
    assert is_nil(workflow["profile_kind"])
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

  test "disabled raw route mappings do not shadow lifecycle route fallback for issue capabilities" do
    profile =
      ProfileRegistry.resolve!(%{
        "kind" => "coding_pr_delivery",
        "version" => 1,
        "options" => %{"routes" => %{"rework" => %{"enabled" => false}}}
      })

    settings = %{
      workflow: %{profile: %{"kind" => profile.kind, "version" => profile.version, "options" => profile.options}},
      tracker: %{
        lifecycle: %{
          raw_state_by_route_key: %{"rework" => "Merging"},
          state_phase_map: %{"Merging" => "merging"}
        }
      }
    }

    issue = %{state: "Merging", lifecycle_phase: "merging"}

    assert {:ok, capabilities, ^profile} = Capabilities.required_capabilities_for_issue(settings, issue)
    assert "repo_provider.merge" in capabilities
  end

  test "issue capabilities read issue workflow policy as effective facts" do
    settings = %{
      workflow: %{profile: ProfileRegistry.default_profile_config()},
      tracker: %{
        lifecycle: %{
          raw_state_by_route_key: %{"merging" => "Merging"},
          state_phase_map: %{"Merging" => "merging"}
        }
      }
    }

    issue = %{
      state: "Merging",
      lifecycle_phase: "merging",
      workflow: %{policy_by_route_key: %{merging: %{action: :wait}}}
    }

    raw_issue = %{
      issue
      | workflow: %{policy_by_route_key: %{"merging" => %{"action" => "wait"}}}
    }

    assert {:ok, effective_capabilities, _profile} = Capabilities.required_capabilities_for_issue(settings, issue)
    refute "repo_provider.merge" in effective_capabilities

    assert {:ok, raw_capabilities, _profile} = Capabilities.required_capabilities_for_issue(settings, raw_issue)
    assert "repo_provider.merge" in raw_capabilities
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

  test "readiness facts read issue workflow policy as effective facts" do
    issue =
      issue_for_route("Merging", "merging", %{
        merging: "Merging"
      })

    effective_issue = %{issue | workflow: Map.put(issue.workflow, :policy_by_route_key, %{merging: %{action: :wait}})}

    raw_issue = %{
      issue
      | workflow: Map.put(issue.workflow, :policy_by_route_key, %{"merging" => %{"action" => "wait"}})
    }

    effective_facts = Readiness.facts(effective_issue)
    raw_facts = Readiness.facts(raw_issue)

    assert effective_facts["route"]["action"] == "wait"
    refute "repo_provider.merge" in effective_facts["capabilities"]["conditional"]

    assert raw_facts["route"]["action"] == "dispatch"
    assert raw_facts["route"]["execution_profile"] == "land"
    assert "repo_provider.merge" in raw_facts["capabilities"]["conditional"]
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
    assert result["workflow_profile"] == "coding_pr_delivery"
    assert result["workflow_profile_version"] == 1
    assert result["workflow_route_key"] == "review"
    refute Map.has_key?(result, "profile")
    refute Map.has_key?(result, "route")
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
    assert result["workflow_route_key"] == "developing"
    refute Map.has_key?(result, "profile")
    refute Map.has_key?(result, "route")
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
