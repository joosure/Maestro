defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ReconciliationTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Orchestrator.BlockedResourceRegistry
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand
  alias SymphonyElixir.Workflow.Extension.Runtime.Projection, as: RuntimeProjection
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ReferenceExtractor
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.StateStoreBackend
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox.Admin, as: InboxAdmin

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.{
    StartupBacklogBootstrap,
    TrackerToolResultHandler,
    Watcher
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.{
    Config,
    Decision,
    Facts,
    ProviderFacts
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input, as: RuntimeInput
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ToolResultRecorder
  alias SymphonyElixir.Workflow.RouteRef

  setup do
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :memory_repo_provider_pr)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_issue_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_review_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_reviews)
      Application.delete_env(:symphony_elixir, :memory_repo_change_proposal_checks)
      Application.delete_env(:symphony_elixir, :memory_tracker_issue_state_overrides)
      Application.delete_env(:symphony_elixir, :coding_pr_delivery_known_target_watcher)
      Application.delete_env(:symphony_elixir, :coding_pr_delivery_startup_backlog_bootstrap)
    end)

    :ok
  end

  test "configuration is disabled by default" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      repo_provider_kind: "memory"
    )

    settings = SymphonyElixir.Config.settings!()

    assert {:ok, %Config{enabled?: false}} = Config.from_settings(settings)
  end

  test "configuration validation rejects unknown route keys" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      repo_provider_kind: "memory",
      workflow_reconciliation: %{
        "change_proposal" => %{
          "enabled" => true,
          "candidates" => %{
            "source_routes" => ["review"]
          },
          "outcome_routes" => %{
            "ready" => "not-a-route"
          }
        }
      }
    )

    assert {:error, {:invalid_workflow_config, message}} = SymphonyElixir.Config.validate!()
    assert message =~ "outcome_routes.ready"
  end

  test "configuration validation rejects static candidate issue ids" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "issue_ids" => ["issue-ready"]
        }
      }
    )

    assert {:error, {:invalid_workflow_config, message}} = SymphonyElixir.Config.validate!()
    assert message =~ "candidates.issue_ids"
  end

  test "configuration validation rejects invalid candidate discovery mode" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "unsafe_scan"
        }
      }
    )

    assert {:error, {:invalid_workflow_config, message}} = SymphonyElixir.Config.validate!()
    assert message =~ "candidates.discovery"
  end

  test "configuration validation rejects unknown nested change proposal fields" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "unknown_limit" => 25
        }
      }
    )

    assert {:error, {:invalid_workflow_config, message}} = SymphonyElixir.Config.validate!()
    assert message =~ "candidates.unknown_limit"
  end

  test "configuration validation rejects removed flat change proposal fields" do
    for {field, value} <- [
          {"source_routes", ["review"]},
          {"ready_target_route", "merging"},
          {"require_approval", true},
          {"candidate_issue_ids", ["issue-ready"]},
          {"max_processed_candidate_issues_per_cycle", 25},
          {"max_candidates_per_tick", 25}
        ] do
      write_memory_reconciliation_workflow!([],
        change_proposal_reconciliation: %{
          field => value
        }
      )

      assert {:error, {:invalid_workflow_config, message}} = SymphonyElixir.Config.validate!()
      assert message =~ field
    end
  end

  test "reconciliation events use tracker kind from supplied settings" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()
    settings = %{settings | tracker: %{settings.tracker | kind: "settings-memory"}}
    state = State.initial(config: settings)

    assert %State{} =
             reconcile(settings, state, fetch_issues_by_states_fn: fn _states, _opts -> {:ok, []} end)

    assert %{
             "event" => "change_proposal_reconciliation_started",
             "tracker_kind" => "settings-memory"
           } = recent_event("change_proposal_reconciliation_started")
  end

  test "configuration validation rejects target routes with incompatible lifecycle phases" do
    for {field, route} <- [
          {"ready", "review"},
          {"already_merged", "rework"},
          {"failed_checks", "resolved"},
          {"changes_requested", "merging"}
        ] do
      write_memory_reconciliation_workflow!([],
        change_proposal_reconciliation: %{
          "outcome_routes" => %{
            field => route
          }
        }
      )

      assert {:error, {:invalid_workflow_config, message}} = SymphonyElixir.Config.validate!()
      assert message =~ "outcome_routes.#{field}"
      assert message =~ route
      assert message =~ "invalid_target_route_lifecycle_phase"
    end
  end

  test "configuration validation rejects target routes with incompatible policy actions" do
    write_memory_reconciliation_workflow!([],
      tracker_policy_by_route_key: %{
        "merging" => %{
          "action" => "wait"
        }
      }
    )

    assert {:error, {:invalid_workflow_config, message}} = SymphonyElixir.Config.validate!()
    assert message =~ "outcome_routes.ready"
    assert message =~ "merging"
    assert message =~ "invalid_target_route_policy_action"
  end

  test "decision covers the default change-proposal reconciliation matrix" do
    config = reconciliation_config()
    retryable_error = %RuntimeError{message: "timeout"}
    non_retryable_error = %RuntimeError{message: "bad request"}

    cases = [
      {"missing change proposal", %Facts{}, %{}, :noop, :missing_change_proposal, nil},
      {"provider state unknown", %{ready_facts() | provider_state: :unknown}, %{}, :provider_retry_later, :provider_state_unknown, nil},
      {"retryable provider error", %{ready_facts() | error: retryable_error, retryable?: true}, %{}, :provider_retry_later, :provider_retryable_error, nil},
      {"non-retryable provider error", %{ready_facts() | error: non_retryable_error}, %{}, :blocked, :provider_non_retryable_error, nil},
      {"already merged", %{ready_facts() | provider_state: :merged}, %{}, :move_to_route, :already_merged, :resolved},
      {"closed unmerged", %{ready_facts() | provider_state: :closed}, %{}, :move_to_route, :closed_unmerged, :rework},
      {"unresolved feedback", %{ready_facts() | unresolved_actionable_feedback?: true}, %{}, :noop, :unresolved_feedback, nil},
      {"changes requested", %{ready_facts() | review_summary: :changes_requested}, %{}, :move_to_route, :changes_requested, :rework},
      {"checks pending", %{ready_facts() | check_summary: :pending}, %{}, :noop, :checks_pending, nil},
      {"checks absent", %{ready_facts() | check_summary: :absent}, %{}, :noop, :checks_absent, nil},
      {"checks failing below threshold", %{ready_facts() | check_summary: :failing}, %{failed_checks_count: 1}, :noop, :checks_failing_unconfirmed, nil},
      {"checks failing at threshold", %{ready_facts() | check_summary: :failing}, %{failed_checks_count: 2}, :move_to_route, :checks_failing, :rework},
      {"merge conflict", %{ready_facts() | mergeability_summary: :conflicting}, %{}, :move_to_route, :merge_conflict, :rework},
      {"approval missing", %{ready_facts() | review_summary: :pending}, %{}, :noop, :approval_missing, nil},
      {"checks not passing", %{ready_facts() | check_summary: :unknown}, %{}, :noop, :checks_not_passing, nil},
      {"mergeability not ready", %{ready_facts() | mergeability_summary: :unknown}, %{}, :noop, :mergeability_not_ready, nil},
      {"ready to land", ready_facts(), %{}, :move_to_route, :ready_to_land, :merging}
    ]

    for {name, facts, counters, action, reason, target_route} <- cases do
      decision = Decision.decide(config, nil, %{}, facts, counters)

      assert %Decision{action: ^action, reason: ^reason} = decision, name
      assert decision.target_route_ref == maybe_route_ref(target_route), name
    end
  end

  test "runtime candidate inbox drains bounded deduplicated issue ids" do
    InboxAdmin.reset()

    assert {:ok,
            %{
              accepted_count: 3,
              duplicate_count: 1,
              dropped_count: 0,
              invalid_count: 2,
              queued_count: 3
            }} = Inbox.enqueue_issue_ids(["issue-a", " issue-b ", "issue-a", " ", "issue-c", 42])

    assert Inbox.drain_issue_ids(limit: 2) == ["issue-a", "issue-b"]
    assert Inbox.drain_issue_ids(limit: 2) == ["issue-c"]
    assert Inbox.drain_issue_ids(limit: 2) == []
  end

  test "runtime candidate inbox suspends repeatedly deferred issue ids and reactivates on enqueue" do
    inbox = start_supervised!({Inbox, name: nil, max_defer_count: 2, max_defer_age_ms: 60_000})

    assert {:ok, %{accepted_count: 1, suspended_count: 0}} =
             Inbox.defer_issue_ids(["issue-deferred"],
               server: inbox,
               now_ms: 1_000,
               reason: :source_route_pending,
               route: :developing
             )

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-deferred"]

    assert {:ok, %{accepted_count: 1, suspended_count: 0}} =
             Inbox.defer_issue_ids(["issue-deferred"],
               server: inbox,
               now_ms: 2_000,
               reason: :source_route_pending,
               route: :developing
             )

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-deferred"]

    assert {:ok, %{accepted_count: 0, suspended_count: 1, suspended_issue_ids: ["issue-deferred"]}} =
             Inbox.defer_issue_ids(["issue-deferred"],
               server: inbox,
               now_ms: 3_000,
               reason: :source_route_pending,
               route: :developing
             )

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == []

    assert %{
             deferred_count: 0,
             suspended_count: 1,
             suspended: %{
               "issue-deferred" => %{
                 deferred_count: 3,
                 last_deferred_route: :developing,
                 suspend_reason: :defer_policy_exceeded
               }
             }
           } = Inbox.lifecycle_snapshot(server: inbox)

    assert {:ok, %{accepted_count: 1, reactivated_count: 1}} =
             Inbox.reactivate_issue_ids(["issue-deferred"], server: inbox)

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-deferred"]
    assert %{deferred_count: 0, suspended_count: 0} = Inbox.lifecycle_snapshot(server: inbox)
  end

  test "runtime candidate inbox accepts canonical defer keyword opts" do
    inbox = start_supervised!({Inbox, name: nil, max_defer_count: 2, max_defer_age_ms: 60_000})

    assert {:ok, %{accepted_count: 1, suspended_count: 0}} =
             Inbox.defer_issue_ids(["issue-running"],
               server: inbox,
               now_ms: 1_000,
               reason: :running_or_claimed,
               route: :review
             )

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-running"]

    assert %{
             deferred_count: 1,
             deferred: %{
               "issue-running" => %{
                 deferred_count: 1,
                 defer_reason: :running_or_claimed,
                 last_deferred_route: :review
               }
             }
           } = Inbox.lifecycle_snapshot(server: inbox)
  end

  test "runtime candidate inbox rejects invalid options and missing server with bounded errors" do
    inbox = start_supervised!({Inbox, name: nil})

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_options",
              reason: :options_not_keyword,
              value_type: "list"
            }} = Inbox.enqueue_issue_ids(["issue-a"], [:not_keyword])

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_issue_ids",
              reason: :issue_ids_not_list,
              value_type: "map"
            }} = Inbox.enqueue_issue_ids(%{"id" => "issue-a"})

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_options",
              reason: :options_not_keyword,
              value_type: "map"
            }} = Inbox.defer_issue_ids(["issue-a"], %{reason: :running_or_claimed})

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_options",
              reason: :invalid_drain_limit,
              value_type: "integer"
            }} = Inbox.drain_issue_ids(limit: 0, server: inbox)

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_options",
              reason: :invalid_max_defer_count,
              value_type: "string"
            }} = Inbox.defer_issue_ids(["issue-a"], server: inbox, max_defer_count: "bad")

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_options",
              reason: :invalid_queue_limit,
              value_type: "integer"
            }} = Inbox.start_link(name: nil, queue_limit: 0)

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_options",
              reason: :invalid_max_defer_age_ms,
              value_type: "integer"
            }} = Inbox.start_link(name: nil, max_defer_age_ms: -1)

    assert {:error,
            %{
              code: "coding_pr_delivery_candidate_inbox_unavailable",
              reason: :candidate_inbox_unavailable,
              server_type: "atom"
            }} = Inbox.drain_issue_ids(server: :missing_candidate_inbox)

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_candidate_inbox_options",
              reason: :options_not_keyword,
              value_type: "integer"
            }} = Inbox.drain_issue_ids(-1)

    assert {:error,
            %{
              code: "coding_pr_delivery_candidate_inbox_unavailable",
              reason: :candidate_inbox_unavailable,
              server_type: "atom"
            }} = Inbox.lifecycle_snapshot(server: :missing_candidate_inbox)

    assert {:error,
            %{
              code: "coding_pr_delivery_candidate_inbox_unavailable",
              reason: :candidate_inbox_unavailable,
              server_type: "atom"
            }} = InboxAdmin.reset(server: :missing_candidate_inbox)
  end

  test "known target registration stores bounded change proposal metadata and enqueues issue id" do
    assert {:ok,
            %{
              target: target,
              enqueue: %{accepted_count: 1, queued_count: 1}
            }} =
             Reconciliation.register_known_target(%{
               "issue_id" => " issue-known ",
               "tracker_kind" => "tapd",
               "repo_provider_kind" => "cnb",
               "repository" => "acme/widgets",
               "url" => "https://cnb.cool/acme/widgets/-/pulls/35"
             })

    assert target.issue_id == "issue-known"
    assert target.number == "35"
    assert target.repo_provider_kind == "cnb"
    assert target.repository == "acme/widgets"

    assert [^target] = Reconciliation.known_targets()
    assert Inbox.drain_issue_ids(limit: 10) == ["issue-known"]
  end

  test "known target registration releases active typed-tool blocker for the same issue" do
    blocked_registry = start_supervised!({BlockedResourceRegistry, name: nil, persistence_path: false})

    assert {:ok, _record} =
             BlockedResourceRegistry.register(
               %{
                 "resource_kind" => "tracker_issue",
                 "resource_id" => "issue-known-unblocked",
                 "blocker_code" => "review_handoff_blocked_after_retries"
               },
               server: blocked_registry
             )

    assert BlockedResourceRegistry.active_for_issue?("issue-known-unblocked", server: blocked_registry)

    assert {:ok, %{target: %{issue_id: "issue-known-unblocked"}}} =
             Reconciliation.register_known_target(
               known_target_attrs("issue-known-unblocked"),
               command_handler: blocked_resource_command_handler(blocked_registry)
             )

    refute BlockedResourceRegistry.active_for_issue?("issue-known-unblocked", server: blocked_registry)

    assert %{
             "status" => "released",
             "release_reason" => "known_target_updated"
           } =
             BlockedResourceRegistry.snapshot(server: blocked_registry)
             |> Enum.find(fn record -> get_in(record, ["resource", "id"]) == "issue-known-unblocked" end)
  end

  test "known target registration rejects non-keyword opts" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_registration_options",
              reason: :options_not_keyword,
              value_type: "list"
            }} = Reconciliation.register_known_target(known_target_attrs("issue-invalid-registration-opts"), [:not_keyword])
  end

  test "known target registration bounds invalid command handler results" do
    registry = start_supervised!({KnownTarget.Registry, name: nil})
    inbox = start_supervised!({Inbox, name: nil})

    assert {:error, {:invalid_runtime_command_result, %{result_type: :map}}} =
             Reconciliation.register_known_target(
               known_target_attrs("issue-invalid-command-result"),
               registry: registry,
               inbox: inbox,
               command_handler: fn _command -> %{secret: "hidden"} end
             )
  end

  test "known target registry evicts oldest targets when max target count is exceeded" do
    registry = start_supervised!({KnownTarget.Registry, name: nil, max_targets: 2})

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-oldest"),
               server: registry,
               now_ms: 1
             )

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-middle"),
               server: registry,
               now_ms: 2
             )

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-newest"),
               server: registry,
               now_ms: 3
             )

    assert is_nil(KnownTarget.Registry.get("issue-oldest", server: registry))
    assert ["issue-newest", "issue-middle"] = registry_issue_ids(registry)
  end

  test "known target registry can prune stale targets by configured ttl" do
    registry = start_supervised!({KnownTarget.Registry, name: nil, target_ttl_ms: 100})

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-expired"),
               server: registry,
               now_ms: 1_000
             )

    assert %{issue_id: "issue-expired"} =
             KnownTarget.Registry.get("issue-expired", server: registry, now_ms: 1_099)

    assert is_nil(KnownTarget.Registry.get("issue-expired", server: registry, now_ms: 1_100))
  end

  test "known target registry persists canonical targets to extension state" do
    scope = workflow_scope("known-target-persistence")
    {:ok, registry} = KnownTarget.Registry.start_link(name: nil, workflow_scope: scope)

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-persisted"),
               server: registry,
               now_ms: 1_000
             )

    GenServer.stop(registry)

    {:ok, restored} = KnownTarget.Registry.start_link(name: nil, workflow_scope: scope)

    assert %{
             issue_id: "issue-persisted",
             number: "persisted-35",
             repository: "acme/widgets"
           } = KnownTarget.Registry.get("issue-persisted", server: restored)
  end

  test "known target StateStore storage rejects non-json workflow scope" do
    {:ok, target} = KnownTarget.new(known_target_attrs("issue-invalid-scope"))

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_workflow_scope",
              reason: {:invalid_workflow_scope_value, :pid}
            }} =
             StateStoreBackend.put(target,
               workflow_scope: Map.put(workflow_scope("invalid-scope"), "runtime_pid", self())
             )
  end

  test "known target StateStore storage rejects non-keyword opts" do
    {:ok, target} = KnownTarget.new(known_target_attrs("issue-invalid-opts"))

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_storage_options",
              reason: :opts_not_keyword,
              value_type: "list"
            }} = StateStoreBackend.put(target, [{"workflow_scope", workflow_scope("invalid-opts")}])
  end

  test "known target StateStore storage rejects invalid put_many targets" do
    {:ok, target} = KnownTarget.new(known_target_attrs("issue-valid-put-many"))

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_storage_target",
              reason: :invalid_known_target_storage_target,
              value_type: "map"
            }} =
             StateStoreBackend.put_many([target, %{issue_id: "issue-invalid"}],
               workflow_scope: workflow_scope("invalid-put-many")
             )
  end

  test "known target StateStore storage ignores extension_id namespace override" do
    scope = workflow_scope("extension-id-override")
    {:ok, target} = KnownTarget.new(known_target_attrs("issue-extension-id-override"))

    assert :ok = StateStoreBackend.put(target, workflow_scope: scope, extension_id: "test.other_extension")

    assert {:ok, [%KnownTarget{issue_id: "issue-extension-id-override"}]} =
             StateStoreBackend.load(workflow_scope: scope)
  end

  test "known target registration observes runtime inbox drops" do
    registry = start_supervised!({KnownTarget.Registry, name: nil})
    inbox = start_supervised!({Inbox, name: nil, queue_limit: 1})

    assert {:ok, %{accepted_count: 1}} = Inbox.enqueue_issue_ids(["issue-existing"], server: inbox)

    assert {:ok,
            %{
              target: %{issue_id: "issue-dropped", last_enqueued_at_ms: nil},
              enqueue: %{dropped_count: 1}
            }} =
             Reconciliation.register_known_target(
               known_target_attrs("issue-dropped"),
               registry: registry,
               inbox: inbox,
               now_ms: 1_000
             )

    assert %{last_enqueued_at_ms: nil} = KnownTarget.Registry.get("issue-dropped", server: registry)

    assert %{
             "dropped_count" => 1,
             "event" => "change_proposal_candidate_enqueue_dropped",
             "issue_id" => "issue-dropped",
             "level" => "warning",
             "producer" => "known_target_registry"
           } = recent_event("change_proposal_candidate_enqueue_dropped")
  end

  test "tracker attach change proposal recorder registers from workflow capability metadata" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()

    assert :ok =
             record_coding_pr_delivery_tool_result(
               settings.tracker,
               "custom_tracker_attach",
               %{
                 "issue_id" => "issue-attach",
                 "url" => "https://cnb.cool/acme/widgets/-/pulls/42",
                 "reference_kind" => "change_proposal",
                 "provider_kind" => "cnb",
                 "metadata" => %{"repository" => "acme/widgets"}
               },
               {:success, %{"attachment" => %{"url" => "https://cnb.cool/acme/widgets/-/pulls/42"}}},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_attach", "tracker.attach_external_reference")
             )

    assert %{
             issue_id: "issue-attach",
             number: "42",
             url: "https://cnb.cool/acme/widgets/-/pulls/42",
             repo_provider_kind: "cnb",
             repository: "acme/widgets"
           } = KnownTarget.Registry.get("issue-attach")

    assert Inbox.drain_issue_ids(limit: 10) == ["issue-attach"]
  end

  test "tracker attach change proposal recorder stores tracker-canonical issue ids" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()
    tapd_tracker = %{settings.tracker | kind: "tapd"}

    assert :ok =
             record_coding_pr_delivery_tool_result(
               tapd_tracker,
               "custom_tracker_attach",
               %{
                 "issue_id" => "TAPD-1153000000000000001",
                 "url" => "https://cnb.cool/acme/widgets/-/pulls/42",
                 "reference_kind" => "change_proposal"
               },
               {:success, %{"attachment" => %{"url" => "https://cnb.cool/acme/widgets/-/pulls/42"}}},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_attach", "tracker.attach_external_reference")
             )

    assert %{issue_id: "1153000000000000001"} = KnownTarget.Registry.get("1153000000000000001")
    assert is_nil(KnownTarget.Registry.get("TAPD-1153000000000000001"))
    assert Inbox.drain_issue_ids(limit: 10) == ["1153000000000000001"]
  end

  test "tracker attach change proposal recorder prefers canonical issue id from tool payload" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()
    tapd_tracker = %{settings.tracker | kind: "tapd"}

    assert :ok =
             record_coding_pr_delivery_tool_result(
               tapd_tracker,
               "custom_tracker_attach",
               %{
                 "issue_id" => "TAPD-1153000000000000001",
                 "url" => "https://cnb.cool/acme/widgets/-/pulls/42",
                 "reference_kind" => "change_proposal"
               },
               {:success,
                %{
                  "issue" => %{"id" => "1153000000000000001", "identifier" => "TAPD-1153000000000000001"},
                  "attachment" => %{"url" => "https://cnb.cool/acme/widgets/-/pulls/42"}
                }},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_attach", "tracker.attach_external_reference")
             )

    assert %{issue_id: "1153000000000000001"} = KnownTarget.Registry.get("1153000000000000001")
    assert Inbox.drain_issue_ids(limit: 10) == ["1153000000000000001"]
  end

  test "tracker tool recorder does not infer recorder action from tool name suffix" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()

    assert :ok =
             record_coding_pr_delivery_tool_result(
               settings.tracker,
               "custom_attach_external_reference",
               %{
                 "issue_id" => "issue-suffix-only",
                 "url" => "https://cnb.cool/acme/widgets/-/pulls/44",
                 "reference_kind" => "change_proposal",
                 "provider_kind" => "cnb",
                 "metadata" => %{"repository" => "acme/widgets"}
               },
               {:success, %{"attachment" => %{"url" => "https://cnb.cool/acme/widgets/-/pulls/44"}}},
               settings: settings
             )

    assert is_nil(KnownTarget.Registry.get("issue-suffix-only"))
    assert Inbox.drain_issue_ids(limit: 10) == []
    refute tracker_tool_result_ignored_event("custom_attach_external_reference")
  end

  test "tracker tool recorder emits missing capability skips only in diagnostics mode" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()

    assert :ok =
             record_coding_pr_delivery_tool_result(
               settings.tracker,
               "custom_attach_external_reference",
               %{
                 "issue_id" => "issue-diagnostics",
                 "url" => "https://cnb.cool/acme/widgets/-/pulls/45",
                 "reference_kind" => "change_proposal",
                 "provider_kind" => "cnb",
                 "metadata" => %{"repository" => "acme/widgets"}
               },
               {:success, %{"attachment" => %{"url" => "https://cnb.cool/acme/widgets/-/pulls/45"}}},
               settings: settings,
               tracker_tool_result_diagnostics?: true
             )

    assert %{
             "dynamic_tool_name" => "custom_attach_external_reference",
             "ignore_reason" => "missing_workflow_capability",
             "issue_id" => "issue-diagnostics",
             "level" => "debug",
             "producer" => "tracker_tool_result"
           } = tracker_tool_result_ignored_event("custom_attach_external_reference")
  end

  test "tracker tool recorder emits bounded diagnostics for invalid option bags without leaking payload" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()

    assert :ok =
             TrackerToolResultHandler.record(
               settings.tracker,
               "custom_tracker_attach",
               %{
                 "issue_id" => "issue-invalid-tracker-tool-opts",
                 "url" => "https://cnb.cool/acme/widgets/-/pulls/45",
                 "reference_kind" => "change_proposal",
                 "metadata" => %{"repository" => "acme/widgets"}
               },
               {:success, %{"attachment" => %{"url" => "https://cnb.cool/acme/widgets/-/pulls/45"}}},
               [:not_a_keyword]
             )

    assert is_nil(KnownTarget.Registry.get("issue-invalid-tracker-tool-opts"))

    assert %{
             "dynamic_tool_name" => "custom_tracker_attach",
             "error" => error,
             "ignore_reason" => "invalid_options",
             "level" => "warning",
             "producer" => "tracker_tool_result"
           } = tracker_tool_result_ignored_event("custom_tracker_attach")

    assert error =~ "reason=invalid_options"
    assert error =~ "value_type=list"
    refute error =~ "not_a_keyword"
    refute error =~ "issue-invalid-tracker-tool-opts"
  end

  test "tracker tool recorder registration failures are observed without failing tool result recording" do
    write_memory_reconciliation_workflow!([])
    settings = SymphonyElixir.Config.settings!()

    assert :ok =
             record_coding_pr_delivery_tool_result(
               settings.tracker,
               "custom_tracker_attach",
               %{
                 "issue_id" => "issue-registration-failure",
                 "url" => "https://cnb.cool/acme/widgets/-/pulls/46",
                 "reference_kind" => "change_proposal",
                 "provider_kind" => "cnb",
                 "metadata" => %{"repository" => "acme/widgets"}
               },
               {:success, %{"attachment" => %{"url" => "https://cnb.cool/acme/widgets/-/pulls/46"}}},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_attach", "tracker.attach_external_reference"),
               register_known_target_fn: fn _attrs, _opts -> {:error, :registry_down} end
             )

    assert %{
             "dynamic_tool_name" => "custom_tracker_attach",
             "error" => "reason=registry_down",
             "ignore_reason" => "known_target_registration_failed",
             "issue_id" => "issue-registration-failure",
             "level" => "warning",
             "producer" => "tracker_tool_result"
           } = tracker_tool_result_ignored_event("custom_tracker_attach")
  end

  test "tracker move issue recorder registers review-route issues with existing change proposal reference" do
    issue =
      memory_issue(%{
        "id" => "issue-review-reference",
        "identifier" => "MEM-REVIEW-REFERENCE",
        "title" => "Review issue with change proposal",
        "state" => "In Review",
        "workflow" => %{
          "change_proposal" => %{
            "url" => "https://example.test/acme/widgets/-/pulls/43",
            "branch" => "feature/review-reference"
          }
        }
      })

    write_memory_reconciliation_workflow!([issue],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    settings = SymphonyElixir.Config.settings!()

    assert :ok =
             record_coding_pr_delivery_tool_result(
               settings.tracker,
               "custom_tracker_move",
               %{"issue_id" => "issue-review-reference", "state_name" => "review"},
               {:success,
                %{
                  "issue" => %{
                    "id" => "issue-review-reference",
                    "state" => "In Review",
                    "workflow" => %{
                      "change_proposal" => %{
                        "url" => "https://example.test/acme/widgets/-/pulls/43",
                        "branch" => "feature/review-reference"
                      }
                    }
                  }
                }},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_move", "tracker.move_issue"),
               env: [probe: :review_transition_fetch],
               producer_private_probe: :must_not_reach_tracker,
               tracker_fetch_issue_states_by_ids_fn: fn _tracker, ["issue-review-reference"], opts ->
                 flunk("move recorder should use issue payload before fetching by arguments; got #{inspect(opts)}")
               end
             )

    assert %{
             issue_id: "issue-review-reference",
             number: "43",
             branch: "feature/review-reference"
           } = KnownTarget.Registry.get("issue-review-reference")

    assert Inbox.drain_issue_ids(limit: 10) == ["issue-review-reference"]
  end

  test "tracker move issue recorder rejects invalid known target registry opts" do
    issue =
      memory_issue(%{
        "id" => "issue-invalid-registry-opts",
        "identifier" => "MEM-INVALID-REGISTRY-OPTS",
        "title" => "Review issue with invalid registry opts",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    settings = SymphonyElixir.Config.settings!()

    assert :ok =
             record_coding_pr_delivery_tool_result(
               settings.tracker,
               "custom_tracker_move",
               %{"issue_id" => "issue-invalid-registry-opts", "state_name" => "review"},
               {:success,
                %{
                  "issue" => %{
                    "id" => "issue-invalid-registry-opts",
                    "state" => "In Review"
                  }
                }},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_move", "tracker.move_issue"),
               known_target_registry_opts: [:not_a_keyword]
             )

    assert is_nil(KnownTarget.Registry.get("issue-invalid-registry-opts"))
    assert Inbox.drain_issue_ids(limit: 10) == []

    assert %{
             "dynamic_tool_name" => "custom_tracker_move",
             "error" => error,
             "ignore_reason" => "invalid_options",
             "producer" => "tracker_tool_result"
           } = tracker_tool_result_ignored_event("custom_tracker_move")

    assert error =~ "reason=invalid_known_target_registry_opts"
    assert error =~ "detail_type=list"
    refute error =~ "not_a_keyword"
  end

  test "tracker move issue recorder reuses internal known target for canonical tracker issue ids" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    settings = SymphonyElixir.Config.settings!()
    tapd_tracker = %{settings.tracker | kind: "tapd"}

    assert {:ok, _target} =
             KnownTarget.Registry.register(%{
               "issue_id" => "1153000000000000001",
               "url" => "https://cnb.cool/acme/widgets/-/pulls/42",
               "repo_provider_kind" => "cnb",
               "repository" => "acme/widgets"
             })

    assert :ok =
             record_coding_pr_delivery_tool_result(
               tapd_tracker,
               "custom_tracker_move",
               %{"issue_id" => "TAPD-1153000000000000001", "state_name" => "review"},
               {:success,
                %{
                  "issue" => %{
                    "id" => "1153000000000000001",
                    "identifier" => "TAPD-1153000000000000001",
                    "state" => %{"id" => "In Review", "name" => "In Review", "type" => "human_review"}
                  }
                }},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_move", "tracker.move_issue"),
               tracker_fetch_issue_states_by_ids_fn: fn _tracker, _issue_ids, _opts ->
                 flunk("move recorder should use canonical issue payload before fetching by arguments")
               end
             )

    assert %{issue_id: "1153000000000000001"} = KnownTarget.Registry.get("1153000000000000001")
    assert is_nil(KnownTarget.Registry.get("TAPD-1153000000000000001"))
    assert Inbox.drain_issue_ids(limit: 10) == ["1153000000000000001"]
  end

  test "tracker move issue recorder prefers canonical moved issue payload over argument fetch" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    settings = SymphonyElixir.Config.settings!()
    tapd_tracker = %{settings.tracker | kind: "tapd"}

    assert {:ok, _target} =
             KnownTarget.Registry.register(%{
               "issue_id" => "1153000000000000001",
               "url" => "https://cnb.cool/acme/widgets/-/pulls/42",
               "repo_provider_kind" => "cnb",
               "repository" => "acme/widgets"
             })

    assert :ok =
             record_coding_pr_delivery_tool_result(
               tapd_tracker,
               "custom_tracker_move",
               %{"issue_id" => "TAPD-1153000000000000001", "state_name" => "review"},
               {:success,
                %{
                  "issue" => %{
                    "id" => "1153000000000000001",
                    "identifier" => "TAPD-1153000000000000001",
                    "state" => %{"id" => "In Review", "name" => "In Review", "type" => "human_review"}
                  }
                }},
               settings: settings,
               tool_context: tracker_tool_context("custom_tracker_move", "tracker.move_issue"),
               tracker_fetch_issue_states_by_ids_fn: fn _tracker, _issue_ids, _opts ->
                 flunk("move recorder should use the canonical issue payload before fetching by arguments")
               end
             )

    assert %{issue_id: "1153000000000000001"} = KnownTarget.Registry.get("1153000000000000001")
    assert Inbox.drain_issue_ids(limit: 10) == ["1153000000000000001"]
  end

  test "known-target watcher enqueues only registered targets when provider facts change" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    put_ready_repo_provider_payloads()

    Application.put_env(:symphony_elixir, :memory_repo_change_proposal_checks, [
      %{"name" => "ci", "status" => "queued", "conclusion" => nil}
    ])

    assert {:ok, %{target: %{issue_id: "issue-watch"}}} =
             Reconciliation.register_known_target(
               %{
                 "issue_id" => "issue-watch",
                 "tracker_kind" => "memory",
                 "repo_provider_kind" => "memory",
                 "repository" => "acme/widgets",
                 "number" => "35"
               },
               now_ms: 1_000
             )

    assert Inbox.drain_issue_ids(limit: 10) == ["issue-watch"]

    assert %{
             inspected_count: 1,
             enqueued_count: 1,
             changed_count: 1,
             due_count: 0,
             error_count: 0
           } =
             Watcher.run_once(
               now_ms: 1_001,
               enqueue_unchanged_after_ms: 300_000,
               command_handler: noop_command_handler()
             )

    assert Inbox.drain_issue_ids(limit: 10) == ["issue-watch"]

    assert %{
             inspected_count: 1,
             enqueued_count: 0,
             changed_count: 0,
             due_count: 0,
             error_count: 0
           } =
             Watcher.run_once(
               now_ms: 1_002,
               enqueue_unchanged_after_ms: 300_000,
               command_handler: noop_command_handler()
             )

    assert Inbox.drain_issue_ids(limit: 10) == []

    Application.put_env(:symphony_elixir, :memory_repo_change_proposal_checks, [
      %{"name" => "ci", "status" => "completed", "conclusion" => "success"}
    ])

    assert %{
             inspected_count: 1,
             enqueued_count: 1,
             changed_count: 1,
             due_count: 0,
             error_count: 0
           } =
             Watcher.run_once(
               now_ms: 1_003,
               enqueue_unchanged_after_ms: 300_000,
               command_handler: noop_command_handler()
             )

    assert Inbox.drain_issue_ids(limit: 10) == ["issue-watch"]
  end

  test "known-target watcher releases active typed-tool blocker when provider facts change" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    registry = start_supervised!({KnownTarget.Registry, name: nil})
    inbox = start_supervised!({Inbox, name: nil})
    blocked_registry = start_supervised!({BlockedResourceRegistry, name: nil, persistence_path: false})

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-watch-unblocked"),
               server: registry,
               now_ms: 1_000
             )

    assert {:ok, _record} =
             BlockedResourceRegistry.register(
               %{
                 "resource_kind" => "tracker_issue",
                 "resource_id" => "issue-watch-unblocked",
                 "blocker_code" => "review_handoff_blocked_after_retries"
               },
               server: blocked_registry
             )

    assert %{
             inspected_count: 1,
             enqueued_count: 1,
             changed_count: 1,
             due_count: 1,
             error_count: 0
           } =
             Watcher.run_once(
               registry: registry,
               inbox: inbox,
               command_handler: blocked_resource_command_handler(blocked_registry),
               now_ms: 1_001,
               change_proposal_facts_fn: fn _repo, _target, _opts -> ready_facts() end
             )

    refute BlockedResourceRegistry.active_for_issue?("issue-watch-unblocked", server: blocked_registry)
  end

  test "startup backlog bootstrap enqueues source-route issues for runtime targeted reconciliation" do
    review_issue =
      memory_issue(%{
        "id" => "issue-bootstrap-review",
        "identifier" => "MEM-BOOTSTRAP-REVIEW",
        "title" => "Existing review issue",
        "state" => "In Review"
      })

    active_issue =
      memory_issue(%{
        "id" => "issue-bootstrap-active",
        "identifier" => "MEM-BOOTSTRAP-ACTIVE",
        "title" => "Active issue",
        "state" => "In Progress"
      })

    write_memory_reconciliation_workflow!([review_issue, active_issue],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    inbox = start_supervised!({Inbox, name: nil})

    assert %{status: :ok, candidate_count: 1, enqueued_count: 1} =
             StartupBacklogBootstrap.run_once(inbox: inbox)

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-bootstrap-review"]
  end

  test "startup backlog bootstrap returns bounded error for invalid options" do
    assert %{status: :error, candidate_count: 0, enqueued_count: 0, error: error} =
             StartupBacklogBootstrap.run_once([:not_a_keyword])

    assert error =~ "reason=invalid_options"
    assert error =~ "value_type=list"
    refute error =~ "not_a_keyword"
  end

  test "startup backlog bootstrap validates injected dependency arity" do
    assert %{status: :error, candidate_count: 0, enqueued_count: 0, error: error} =
             StartupBacklogBootstrap.run_once(settings_fn: fn _unexpected -> {:ok, %{}} end)

    assert error =~ "reason=invalid_dependency"
    assert error =~ "dependency=settings_fn"
    assert error =~ "expected_arity=0"
    refute error =~ "unexpected"
  end

  test "known-target watcher observes provider inspect exceptions" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    registry = start_supervised!({KnownTarget.Registry, name: nil})
    inbox = start_supervised!({Inbox, name: nil})

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-watch-error"),
               server: registry,
               now_ms: 1_000
             )

    assert %{
             inspected_count: 1,
             enqueued_count: 0,
             changed_count: 0,
             due_count: 0,
             error_count: 1
           } =
             Watcher.run_once(
               registry: registry,
               inbox: inbox,
               command_handler: noop_command_handler(),
               now_ms: 1_001,
               change_proposal_facts_fn: fn _repo, _target, _opts ->
                 raise "provider inspect unavailable"
               end
             )

    assert %{
             "event" => "change_proposal_known_target_watcher_failed",
             "issue_id" => "issue-watch-error",
             "level" => "warning",
             "producer" => "known_target_watcher"
           } = recent_event("change_proposal_known_target_watcher_failed")
  end

  test "known-target watcher returns bounded empty result for invalid options" do
    assert %{
             inspected_count: 0,
             enqueued_count: 0,
             changed_count: 0,
             due_count: 0,
             error_count: 1
           } = Watcher.run_once([:not_a_keyword])
  end

  test "known-target watcher validates injected dependency arity" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    assert %{
             inspected_count: 0,
             enqueued_count: 0,
             changed_count: 0,
             due_count: 0,
             error_count: 1
           } =
             Watcher.run_once(
               command_handler: noop_command_handler(),
               change_proposal_facts_fn: fn _repo -> ready_facts() end
             )
  end

  test "known-target watcher observes runtime inbox drops" do
    write_memory_reconciliation_workflow!([],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    registry = start_supervised!({KnownTarget.Registry, name: nil})
    inbox = start_supervised!({Inbox, name: nil, queue_limit: 1})

    assert {:ok, %{accepted_count: 1}} = Inbox.enqueue_issue_ids(["issue-existing"], server: inbox)

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-watch-dropped"),
               server: registry,
               now_ms: 1_000
             )

    assert %{
             inspected_count: 1,
             enqueued_count: 0,
             changed_count: 1,
             due_count: 1,
             error_count: 1
           } =
             Watcher.run_once(
               registry: registry,
               inbox: inbox,
               command_handler: noop_command_handler(),
               now_ms: 1_001,
               change_proposal_facts_fn: fn _repo, _target, _opts -> ready_facts() end
             )

    assert %{
             "dropped_count" => 1,
             "event" => "change_proposal_candidate_enqueue_dropped",
             "issue_id" => "issue-watch-dropped",
             "level" => "warning",
             "producer" => "known_target_watcher"
           } = recent_event("change_proposal_candidate_enqueue_dropped")

    assert %{last_enqueued_at_ms: nil} = KnownTarget.Registry.get("issue-watch-dropped", server: registry)
  end

  test "known-target watcher does not inspect providers unless runtime-targeted reconciliation is active" do
    write_memory_reconciliation_workflow!([])

    assert {:ok, %{target: %{issue_id: "issue-source-scan"}}} =
             Reconciliation.register_known_target(%{
               "issue_id" => "issue-source-scan",
               "tracker_kind" => "memory",
               "repo_provider_kind" => "memory",
               "repository" => "acme/widgets",
               "number" => "35"
             })

    assert Inbox.drain_issue_ids(limit: 10) == ["issue-source-scan"]

    assert %{
             inspected_count: 0,
             enqueued_count: 0,
             changed_count: 0,
             due_count: 0,
             error_count: 0
           } =
             Watcher.run_once(
               change_proposal_facts_fn: fn _repo, _target, _opts ->
                 flunk("watcher must not inspect providers outside runtime_targeted mode")
               end
             )

    assert Inbox.drain_issue_ids(limit: 10) == []
  end

  test "coding PR delivery reference extractor prefers attached workflow metadata" do
    issue = %Issue{
      id: "issue-reference",
      branch_name: "feature/issue-branch",
      workflow: %{
        "change_proposal" => %{
          "number" => 42,
          "url" => "https://example.test/acme/widgets/-/pulls/42",
          "branch" => "feature/attached"
        }
      }
    }

    assert %KnownTargetReference{
             number: "42",
             url: "https://example.test/acme/widgets/-/pulls/42",
             branch: "feature/attached"
           } = ReferenceExtractor.from_issue(issue)
  end

  test "coding PR delivery reference extractor ignores provider attachment display metadata" do
    issue = %{
      "id" => "issue-attachment-reference",
      "attachments" => [
        %{
          "title" => "Change proposal",
          "url" => "https://example.test/acme/widgets/-/pulls/44"
        }
      ]
    }

    assert is_nil(ReferenceExtractor.from_issue(issue))
  end

  test "reconciler reads known target registry as the internal source of truth" do
    issue =
      memory_issue(%{
        "id" => "issue-known-target-reference",
        "identifier" => "MEM-KNOWN-TARGET-REFERENCE",
        "title" => "Known target change proposal",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue])

    registry = start_supervised!({KnownTarget.Registry, name: nil})

    assert {:ok, _target} =
             KnownTarget.Registry.register(
               Map.merge(known_target_attrs("issue-known-target-reference"), %{
                 "number" => "45",
                 "url" => "https://example.test/acme/widgets/-/pulls/45",
                 "branch" => "feature/known-target"
               }),
               server: registry
             )

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} =
               reconcile(settings, state,
                 known_target_registry: registry,
                 change_proposal_facts_fn: fn _repo, %KnownTarget.Reference{} = reference, _opts ->
                   assert reference.number == "45"
                   assert reference.url == "https://example.test/acme/widgets/-/pulls/45"
                   assert reference.branch == "feature/known-target"

                   %{ready_facts() | number: 45, url: reference.url, branch: reference.branch}
                 end
               )
    end)

    event = recent_issue_event("issue-known-target-reference", "change_proposal_located")

    assert event["change_proposal_number"] == "45"
    assert event["change_proposal_url"] == "https://example.test/acme/widgets/-/pulls/45"
    assert event["change_proposal_branch"] == "feature/known-target"
  end

  test "provider facts service normalizes repo-provider payloads into workflow facts" do
    repo = %{"provider" => %{"kind" => "cnb", "repository" => "acme/widgets"}}

    facts =
      ProviderFacts.facts(repo, %KnownTargetReference{number: "42"},
        pr_view_fn: fn _repo, opts ->
          assert opts == [number: "42"]

          {:ok,
           %{
             "number" => 42,
             "url" => "https://example.test/acme/widgets/-/pulls/42",
             "state" => "OPEN",
             "headRefName" => "feature/ready",
             "headRefOid" => "abc123",
             "mergeable" => "MERGEABLE",
             "mergeStateStatus" => "CLEAN"
           }}
        end,
        pr_issue_comments_fn: fn _repo, _opts -> {:ok, []} end,
        pr_review_comments_fn: fn _repo, _opts -> {:ok, []} end,
        pr_reviews_fn: fn _repo, _opts ->
          {:ok,
           [
             %{
               "state" => "APPROVED",
               "user" => %{"login" => "reviewer"},
               "submitted_at" => "2026-05-12T00:00:00Z"
             }
           ]}
        end,
        pr_checks_fn: fn _repo, _opts ->
          {:ok, [%{"name" => "ci", "status" => "completed", "conclusion" => "success"}]}
        end,
        env: %{}
      )

    assert %Facts{
             provider_kind: "cnb",
             repository: "acme/widgets",
             number: 42,
             branch: "feature/ready",
             head_sha: "abc123",
             provider_state: :open,
             review_summary: :approved,
             check_summary: :passing,
             mergeability_summary: :mergeable,
             unresolved_actionable_feedback?: false
           } = facts
  end

  test "provider facts service rejects non-keyword option bags" do
    repo = %{"provider" => %{"kind" => "cnb", "repository" => "acme/widgets"}}

    facts = ProviderFacts.facts(repo, %KnownTargetReference{number: "42"}, [:not_keyword])

    assert %Facts{
             error: %SymphonyElixir.RepoProvider.Error{
               code: :invalid_provider_facts_options,
               details: %{
                 source_reason:
                   {:invalid_provider_facts_options,
                    %{
                      reason: :opts_not_keyword,
                      value_type: :list
                    }}
               }
             },
             provider_state: :unknown
           } = facts
  end

  test "provider facts service rejects invalid injected provider functions" do
    repo = %{"provider" => %{"kind" => "cnb", "repository" => "acme/widgets"}}

    facts =
      ProviderFacts.facts(repo, %KnownTargetReference{number: "42"}, pr_view_fn: fn _repo -> {:ok, %{}} end)

    assert %Facts{
             error: %SymphonyElixir.RepoProvider.Error{
               code: :invalid_provider_facts_dependency,
               details: %{
                 source_reason:
                   {:invalid_provider_facts_dependency,
                    %{
                      option: :pr_view_fn,
                      expected: "function/2",
                      value_type: :function
                    }}
               }
             }
           } = facts
  end

  test "provider facts service bounds callback exceptions" do
    repo = %{"provider" => %{"kind" => "cnb", "repository" => "acme/widgets"}}

    facts =
      ProviderFacts.facts(repo, %KnownTargetReference{number: "42"}, pr_view_fn: fn _repo, _opts -> raise "do not leak provider payload" end)

    assert %Facts{
             error: %SymphonyElixir.RepoProvider.Error{
               code: :provider_facts_provider_callback_failed,
               details: %{
                 source_reason:
                   {:provider_facts_provider_callback_failed,
                    %{
                      operation: :pr_view,
                      exception: "RuntimeError"
                    }}
               }
             }
           } = facts

    refute facts.error |> inspect() |> String.contains?("do not leak provider payload")
  end

  test "provider facts service bounds invalid provider payload diagnostics" do
    repo = %{"provider" => %{"kind" => "cnb", "repository" => "acme/widgets"}}

    facts =
      ProviderFacts.facts(repo, %KnownTargetReference{number: "42"},
        pr_view_fn: fn _repo, _opts -> {:ok, %{"number" => 42, "state" => "OPEN"}} end,
        pr_issue_comments_fn: fn _repo, _opts -> {:ok, %{"secret" => "do-not-log"}} end
      )

    assert %Facts{
             error: %SymphonyElixir.RepoProvider.Error{
               code: :invalid_repo_provider_payload,
               details: %{
                 source_reason:
                   {:invalid_repo_provider_payload,
                    %{
                      operation: :pr_issue_comments,
                      expected: :list,
                      payload_type: :map
                    }}
               }
             }
           } = facts

    refute facts.error |> inspect() |> String.contains?("do-not-log")
  end

  test "reconciler moves a reviewed green memory PR from review to merging" do
    issue =
      memory_issue(%{
        "id" => "issue-ready",
        "identifier" => "MEM-READY",
        "title" => "Ready change proposal",
        "state" => "In Review",
        "branch_name" => "feature/ready"
      })

    write_memory_reconciliation_workflow!([issue])
    put_ready_repo_provider_payloads()

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    assert %State{} = reconcile(settings, state)
    assert_receive {:memory_tracker_state_update, "issue-ready", "Merging"}
    assert {:ok, [%Issue{state: "Merging"}]} = Tracker.fetch_issue_states_by_ids(["issue-ready"])
  end

  test "reconciler emits standalone event when a change proposal is located" do
    issue =
      memory_issue(%{
        "id" => "issue-located",
        "identifier" => "MEM-LOCATED",
        "title" => "Located change proposal",
        "state" => "In Review"
      })

    reference = %KnownTargetReference{
      number: "42",
      url: "https://example.test/acme/widgets/-/pulls/42",
      branch: "feature/located"
    }

    write_memory_reconciliation_workflow!([issue])

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} =
               reconcile(settings, state,
                 change_proposal_reference_fn: fn _issue, _opts -> {:ok, reference} end,
                 change_proposal_facts_fn: fn _repo, ^reference, _opts ->
                   %{ready_facts() | number: 42, url: reference.url, branch: reference.branch}
                 end
               )
    end)

    event = recent_issue_event("issue-located", "change_proposal_located")

    assert event["issue_identifier"] == "MEM-LOCATED"
    assert event["source_workflow_profile"] == "coding_pr_delivery"
    assert event["source_workflow_profile_version"] == 1
    assert event["source_workflow_route_key"] == "review"
    assert event["source_state"] == "In Review"
    assert event["change_proposal_number"] == "42"
    assert event["change_proposal_url"] == "https://example.test/acme/widgets/-/pulls/42"
    assert event["change_proposal_branch"] == "feature/located"
  end

  test "reconciler emits standalone event when no change proposal reference is found" do
    issue =
      memory_issue(%{
        "id" => "issue-reference-missing",
        "identifier" => "MEM-REFERENCE-MISSING",
        "title" => "Missing change proposal reference",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue])

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} =
               reconcile(settings, state, change_proposal_reference_fn: fn _issue, _opts -> {:ok, nil} end)
    end)

    event = recent_issue_event("issue-reference-missing", "change_proposal_lookup_failed")

    assert event["issue_identifier"] == "MEM-REFERENCE-MISSING"
    assert event["source_workflow_profile"] == "coding_pr_delivery"
    assert event["source_workflow_profile_version"] == 1
    assert event["source_workflow_route_key"] == "review"
    assert event["source_state"] == "In Review"
    assert event["lookup_failure_reason"] == "not_found"
    refute Map.has_key?(event, "error")

    decision = recent_issue_event("issue-reference-missing", "change_proposal_reconciliation_decision")
    assert decision["reason"] == "missing_change_proposal"
  end

  test "reconciler emits standalone event when change proposal lookup errors" do
    issue =
      memory_issue(%{
        "id" => "issue-reference-error",
        "identifier" => "MEM-REFERENCE-ERROR",
        "title" => "Change proposal reference error",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue])

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} =
               reconcile(settings, state, change_proposal_reference_fn: fn _issue, _opts -> {:error, :tracker_timeout} end)
    end)

    event = recent_issue_event("issue-reference-error", "change_proposal_lookup_failed")

    assert event["level"] == "warning"
    assert event["issue_identifier"] == "MEM-REFERENCE-ERROR"
    assert event["lookup_failure_reason"] == "error"
    assert event["error"] =~ "tracker_timeout"

    skipped =
      recent_issue_event(
        "issue-reference-error",
        "change_proposal_reconciliation_candidate_skipped"
      )

    assert skipped["skip_reason"] == "change_proposal_reference_unavailable"
  end

  test "reconciler rejects non-keyword option bags with bounded diagnostics" do
    issue =
      memory_issue(%{
        "id" => "issue-invalid-reconciler-opts",
        "identifier" => "MEM-INVALID-RECONCILER-OPTS",
        "title" => "Invalid reconciler opts",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue])

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} = reconcile(settings, state, [:not_keyword])
    end)

    event = recent_event("change_proposal_reconciliation_completed")

    assert event["level"] == "warning"
    assert event["status"] == "tracker_error"
    assert event["error"] =~ "reason=invalid_options"
    assert event["error"] =~ "value_type=list"
  end

  test "reconciler rejects invalid injected dependency arity with bounded diagnostics" do
    issue =
      memory_issue(%{
        "id" => "issue-invalid-reconciler-dep",
        "identifier" => "MEM-INVALID-RECONCILER-DEP",
        "title" => "Invalid reconciler dep",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue])

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} = reconcile(settings, state, fetch_issues_by_states_fn: fn -> {:ok, []} end)
    end)

    event = recent_event("change_proposal_reconciliation_completed")

    assert event["level"] == "warning"
    assert event["status"] == "tracker_error"
    assert event["error"] =~ "dependency=fetch_issues_by_states_fn"
    assert event["error"] =~ "reason=invalid_dependency"
    assert event["error"] =~ "value_type=function"
  end

  test "reconciler bounds injected reference callback exceptions" do
    issue =
      memory_issue(%{
        "id" => "issue-reference-raise",
        "identifier" => "MEM-REFERENCE-RAISE",
        "title" => "Change proposal reference raises",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue])

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} =
               reconcile(settings, state,
                 change_proposal_reference_fn: fn _issue, _opts ->
                   raise "do not leak reference callback payload"
                 end
               )
    end)

    event = recent_issue_event("issue-reference-raise", "change_proposal_lookup_failed")

    assert event["level"] == "warning"
    assert event["lookup_failure_reason"] == "error"
    assert event["error"] =~ "exception=RuntimeError"
    assert event["error"] =~ "operation=change_proposal_reference"
    refute event["error"] =~ "do not leak reference callback payload"
  end

  test "reconciler leaves pending checks in review" do
    issue =
      memory_issue(%{
        "id" => "issue-pending",
        "identifier" => "MEM-PENDING",
        "title" => "Pending checks",
        "state" => "In Review",
        "branch_name" => "feature/pending"
      })

    write_memory_reconciliation_workflow!([issue])
    put_ready_repo_provider_payloads()

    Application.put_env(:symphony_elixir, :memory_repo_change_proposal_checks, [
      %{"name" => "ci", "status" => "queued", "conclusion" => nil}
    ])

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    assert %State{} = reconcile(settings, state)
    refute_receive {:memory_tracker_state_update, "issue-pending", "Merging"}, 50
    assert {:ok, [%Issue{state: "In Review"}]} = Tracker.fetch_issue_states_by_ids(["issue-pending"])
  end

  test "reconciler uses runtime candidate issue ids instead of route-state scan" do
    selected_issue =
      memory_issue(%{
        "id" => "issue-selected",
        "identifier" => "MEM-SELECTED",
        "title" => "Selected change proposal",
        "state" => "In Review",
        "branch_name" => "feature/selected"
      })

    unselected_issue =
      memory_issue(%{
        "id" => "issue-unselected",
        "identifier" => "MEM-UNSELECTED",
        "title" => "Unselected change proposal",
        "state" => "In Review",
        "branch_name" => "feature/unselected"
      })

    write_memory_reconciliation_workflow!([selected_issue, unselected_issue])

    put_ready_repo_provider_payloads()

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    assert %State{} =
             reconcile(settings, state,
               targeted_issue_ids: ["issue-selected", " ", "issue-selected"],
               fetch_issue_states_by_ids_fn: fn issue_ids, _opts ->
                 assert issue_ids == ["issue-selected"]
                 Tracker.fetch_issue_states_by_ids(issue_ids)
               end,
               fetch_issues_by_states_fn: fn _states, _opts ->
                 flunk("candidate issue ids must avoid source-route scans")
               end
             )

    assert_receive {:memory_tracker_state_update, "issue-selected", "Merging"}
    refute_receive {:memory_tracker_state_update, "issue-unselected", "Merging"}, 50
  end

  test "runtime-targeted candidate discovery does not fall back to source-route scans" do
    issue =
      memory_issue(%{
        "id" => "issue-waiting",
        "identifier" => "MEM-WAITING",
        "title" => "Waiting for provider-safe candidate input",
        "state" => "In Review",
        "branch_name" => "feature/waiting"
      })

    write_memory_reconciliation_workflow!([issue],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    put_ready_repo_provider_payloads()

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    assert %State{} =
             reconcile(settings, state,
               fetch_issues_by_states_fn: fn _states, _opts ->
                 flunk("runtime-targeted discovery must not scan source routes without runtime ids")
               end
             )

    refute_receive {:memory_tracker_state_update, "issue-waiting", "Merging"}, 50
    assert {:ok, [%Issue{state: "In Review"}]} = Tracker.fetch_issue_states_by_ids(["issue-waiting"])
  end

  test "reconciler validates targeted candidates are still in source routes" do
    issue =
      memory_issue(%{
        "id" => "issue-planning",
        "identifier" => "MEM-PLANNING",
        "title" => "No longer in review",
        "state" => "Todo",
        "branch_name" => "feature/planning"
      })

    write_memory_reconciliation_workflow!([issue])

    put_ready_repo_provider_payloads()

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    assert %State{} =
             reconcile(settings, state,
               targeted_issue_ids: ["issue-planning"],
               fetch_issues_by_states_fn: fn _states, _opts ->
                 flunk("candidate issue ids must avoid source-route scans")
               end
             )

    refute_receive {:memory_tracker_state_update, "issue-planning", "Merging"}, 50
    assert {:ok, [%Issue{state: "Todo"}]} = Tracker.fetch_issue_states_by_ids(["issue-planning"])
  end

  test "reconciler does not overwrite a candidate whose state changes after refresh" do
    issue =
      memory_issue(%{
        "id" => "issue-race",
        "identifier" => "MEM-RACE",
        "title" => "State changed during reconciliation",
        "state" => "In Review",
        "branch_name" => "feature/race"
      })

    write_memory_reconciliation_workflow!([issue])
    put_ready_repo_provider_payloads()

    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    assert %State{} =
             reconcile(settings, state,
               targeted_issue_ids: ["issue-race"],
               fetch_issues_by_states_fn: fn _states, _opts ->
                 flunk("targeted reconciliation must avoid source-route scans")
               end,
               fetch_issue_states_by_ids_fn: fn issue_ids, _opts ->
                 fetch_count = Process.get(:race_fetch_count, 0) + 1
                 Process.put(:race_fetch_count, fetch_count)

                 {:ok, issues} = Tracker.fetch_issue_states_by_ids(issue_ids)

                 if fetch_count == 2 do
                   Application.put_env(:symphony_elixir, :memory_tracker_issue_state_overrides, %{
                     "issue-race" => "Rework"
                   })
                 end

                 {:ok, issues}
               end
             )

    refute_receive {:memory_tracker_state_update, "issue-race", "Merging"}, 50
    assert {:ok, [%Issue{state: "Rework"}]} = Tracker.fetch_issue_states_by_ids(["issue-race"])
  end

  test "reconciler passes tracker fetch options to targeted candidate and transition refresh reads" do
    issue =
      memory_issue(%{
        "id" => "issue-fetch-opts",
        "identifier" => "MEM-FETCH-OPTS",
        "title" => "Fetch opts are propagated",
        "state" => "In Review",
        "branch_name" => "feature/fetch-opts"
      })

    write_memory_reconciliation_workflow!([issue])
    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)
    test_pid = self()
    request_fun = fn _request -> {:ok, %{}} end

    assert %State{} =
             reconcile(settings, state,
               targeted_issue_ids: ["issue-fetch-opts"],
               request_fun: request_fun,
               change_proposal_facts_fn: fn _repo, _target, _opts -> ready_facts() end,
               fetch_issues_by_states_fn: fn _states, _opts ->
                 flunk("targeted reconciliation must avoid source-route scans")
               end,
               fetch_issue_states_by_ids_fn: fn issue_ids, opts ->
                 send(test_pid, {:fetch_issue_states_by_ids_opts, Keyword.fetch!(opts, :request_fun)})
                 Tracker.fetch_issue_states_by_ids(issue_ids)
               end
             )

    assert_receive {:fetch_issue_states_by_ids_opts, ^request_fun}
    assert_receive {:fetch_issue_states_by_ids_opts, ^request_fun}
    assert_receive {:fetch_issue_states_by_ids_opts, ^request_fun}
  end

  test "transition update callback failures use bounded diagnostics" do
    issue =
      memory_issue(%{
        "id" => "issue-transition-raise",
        "identifier" => "MEM-TRANSITION-RAISE",
        "title" => "Transition callback raises",
        "state" => "In Review",
        "branch_name" => "feature/transition-raise"
      })

    write_memory_reconciliation_workflow!([issue])
    settings = SymphonyElixir.Config.settings!()
    state = State.initial(config: settings)

    capture_log(fn ->
      assert %State{} =
               reconcile(settings, state,
                 targeted_issue_ids: ["issue-transition-raise"],
                 change_proposal_facts_fn: fn _repo, _target, _opts -> ready_facts() end,
                 fetch_issues_by_states_fn: fn _states, _opts ->
                   flunk("targeted reconciliation must avoid source-route scans")
                 end,
                 update_issue_state_fn: fn _issue_id, _target_state, _opts ->
                   raise "do not leak transition callback payload"
                 end
               )
    end)

    event = recent_issue_event("issue-transition-raise", "change_proposal_transition_failed")

    assert event["level"] == "warning"
    assert event["target_state"] == "Merging"
    assert event["error"]["code"] == "transition_callback_failed"
    assert event["error"]["exception"] == "RuntimeError"
    assert event["error"]["operation"] == "update_issue_state"
    refute inspect(event["error"]) =~ "do not leak transition callback payload"
  end

  test "poll cycle runs reconciliation before normal candidate fetch" do
    issue =
      memory_issue(%{
        "id" => "issue-poll",
        "identifier" => "MEM-POLL",
        "title" => "Poll cycle reconciliation",
        "state" => "In Review",
        "branch_name" => "feature/poll"
      })

    write_memory_reconciliation_workflow!([issue],
      tracker_active_states: ["Todo", "In Progress", "Rework"]
    )

    put_ready_repo_provider_payloads()

    orchestrator_name = __MODULE__.ReconciliationPollOrchestrator
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name, schedule_initial_poll?: false)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    state = :sys.get_state(pid)

    capture_log(fn ->
      assert {:noreply, _returned_state} = Orchestrator.handle_info(:run_poll_cycle, state)
    end)

    assert_receive {:memory_tracker_state_update, "issue-poll", "Merging"}
    assert {:ok, [%Issue{state: "Merging"}]} = Tracker.fetch_issue_states_by_ids(["issue-poll"])
  end

  test "poll cycle drains runtime candidate inbox through the processing limit" do
    first_issue =
      memory_issue(%{
        "id" => "issue-inbox-1",
        "identifier" => "MEM-INBOX-1",
        "title" => "Inbox selected change proposal",
        "state" => "In Review",
        "branch_name" => "feature/inbox-1"
      })

    second_issue =
      memory_issue(%{
        "id" => "issue-inbox-2",
        "identifier" => "MEM-INBOX-2",
        "title" => "Inbox deferred change proposal",
        "state" => "In Review",
        "branch_name" => "feature/inbox-2"
      })

    unqueued_issue =
      memory_issue(%{
        "id" => "issue-inbox-unqueued",
        "identifier" => "MEM-INBOX-UNQUEUED",
        "title" => "Unqueued review issue",
        "state" => "In Review",
        "branch_name" => "feature/inbox-unqueued"
      })

    write_memory_reconciliation_workflow!([first_issue, second_issue, unqueued_issue],
      tracker_active_states: ["Todo", "In Progress", "Rework"],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted",
          "max_processed_issues_per_cycle" => 1
        }
      }
    )

    put_ready_repo_provider_payloads()
    inbox = start_supervised!({Inbox, name: nil})

    assert {:ok, %{accepted_count: 2, queued_count: 2}} =
             Inbox.enqueue_issue_ids(["issue-inbox-1", "issue-inbox-2"],
               server: inbox
             )

    state = State.initial(config: SymphonyElixir.Config.settings!())

    capture_log(fn ->
      assert %State{} =
               SymphonyElixir.Orchestrator.PollCycle.run(state,
                 running_opts: fn _state -> [] end,
                 runtime_extension_opts: %{
                   "symphony.workflow.extension.coding_pr_delivery" => [
                     reconciler_opts: [
                       targeted_issue_ids_fn: fn limit ->
                         Inbox.drain_issue_ids(limit: limit, server: inbox)
                       end
                     ]
                   ]
                 },
                 notify_dashboard: fn -> :ok end
               )
    end)

    assert_receive {:memory_tracker_state_update, "issue-inbox-1", "Merging"}
    refute_receive {:memory_tracker_state_update, "issue-inbox-2", "Merging"}, 50
    refute_receive {:memory_tracker_state_update, "issue-inbox-unqueued", "Merging"}, 50

    assert {:ok,
            [
              %Issue{state: "Merging"},
              %Issue{state: "In Review"},
              %Issue{state: "In Review"}
            ]} =
             Tracker.fetch_issue_states_by_ids([
               "issue-inbox-1",
               "issue-inbox-2",
               "issue-inbox-unqueued"
             ])

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-inbox-2"]
  end

  test "runtime-targeted candidates deferred by running issues are requeued" do
    issue =
      memory_issue(%{
        "id" => "issue-running-target",
        "identifier" => "MEM-RUNNING-TARGET",
        "title" => "Running change proposal target",
        "state" => "In Review",
        "branch_name" => "feature/running-target"
      })

    write_memory_reconciliation_workflow!([issue],
      tracker_active_states: ["Todo", "In Progress", "Rework"],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    put_ready_repo_provider_payloads()
    inbox = start_supervised!({Inbox, name: nil})

    assert {:ok, %{accepted_count: 1}} =
             Inbox.enqueue_issue_ids(["issue-running-target"], server: inbox)

    settings = SymphonyElixir.Config.settings!()
    running_state = %{State.initial(config: settings) | running: %{"issue-running-target" => %{}}}

    assert %State{} =
             reconcile(settings, running_state,
               targeted_issue_ids_fn: fn limit ->
                 Inbox.drain_issue_ids(limit: limit, server: inbox)
               end,
               defer_targeted_issue_ids_fn: fn issue_ids ->
                 Inbox.enqueue_issue_ids(issue_ids, server: inbox)
               end
             )

    refute_receive {:memory_tracker_state_update, "issue-running-target", "Merging"}, 50
    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-running-target"]

    assert {:ok, %{accepted_count: 1}} =
             Inbox.enqueue_issue_ids(["issue-running-target"], server: inbox)

    assert %State{} =
             reconcile(settings, State.initial(config: settings),
               targeted_issue_ids_fn: fn limit ->
                 Inbox.drain_issue_ids(limit: limit, server: inbox)
               end,
               defer_targeted_issue_ids_fn: fn issue_ids ->
                 Inbox.enqueue_issue_ids(issue_ids, server: inbox)
               end
             )

    assert_receive {:memory_tracker_state_update, "issue-running-target", "Merging"}
  end

  test "runtime-targeted known targets remain queued until the source route is reached" do
    issue =
      memory_issue(%{
        "id" => "issue-known-before-review",
        "identifier" => "MEM-KNOWN-BEFORE-REVIEW",
        "title" => "Known change proposal before review",
        "state" => "In Progress",
        "branch_name" => "feature/known-before-review"
      })

    write_memory_reconciliation_workflow!([issue],
      tracker_active_states: ["Todo", "In Progress", "Rework"],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    put_ready_repo_provider_payloads()
    registry = start_supervised!({KnownTarget.Registry, name: nil})
    inbox = start_supervised!({Inbox, name: nil})

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-known-before-review"),
               server: registry
             )

    assert {:ok, %{accepted_count: 1}} =
             Inbox.enqueue_issue_ids(["issue-known-before-review"], server: inbox)

    settings = SymphonyElixir.Config.settings!()

    assert %State{} =
             reconcile(settings, State.initial(config: settings),
               known_target_registry: registry,
               targeted_issue_ids_fn: fn limit ->
                 Inbox.drain_issue_ids(limit: limit, server: inbox)
               end,
               defer_targeted_issue_ids_fn: fn issue_ids ->
                 Inbox.enqueue_issue_ids(issue_ids, server: inbox)
               end
             )

    refute_receive {:memory_tracker_state_update, "issue-known-before-review", "Merging"}, 50
    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == ["issue-known-before-review"]

    Application.put_env(:symphony_elixir, :memory_tracker_issue_state_overrides, %{
      "issue-known-before-review" => "In Review"
    })

    assert {:ok, %{accepted_count: 1}} =
             Inbox.enqueue_issue_ids(["issue-known-before-review"], server: inbox)

    assert %State{} =
             reconcile(settings, State.initial(config: settings),
               known_target_registry: registry,
               targeted_issue_ids_fn: fn limit ->
                 Inbox.drain_issue_ids(limit: limit, server: inbox)
               end,
               defer_targeted_issue_ids_fn: fn issue_ids ->
                 Inbox.enqueue_issue_ids(issue_ids, server: inbox)
               end
             )

    assert_receive {:memory_tracker_state_update, "issue-known-before-review", "Merging"}
  end

  test "runtime-targeted known targets emit suspension event when defer policy is exceeded" do
    issue =
      memory_issue(%{
        "id" => "issue-known-suspended",
        "identifier" => "MEM-KNOWN-SUSPENDED",
        "title" => "Known change proposal suspended before review",
        "state" => "In Progress",
        "branch_name" => "feature/known-suspended"
      })

    write_memory_reconciliation_workflow!([issue],
      tracker_active_states: ["Todo", "In Progress", "Rework"],
      change_proposal_reconciliation: %{
        "candidates" => %{
          "discovery" => "runtime_targeted"
        }
      }
    )

    put_ready_repo_provider_payloads()
    registry = start_supervised!({KnownTarget.Registry, name: nil})
    inbox = start_supervised!({Inbox, name: nil})

    assert {:ok, _target} =
             KnownTarget.Registry.register(known_target_attrs("issue-known-suspended"),
               server: registry
             )

    assert {:ok, %{accepted_count: 1}} =
             Inbox.enqueue_issue_ids(["issue-known-suspended"], server: inbox)

    settings = SymphonyElixir.Config.settings!()

    assert %State{} =
             reconcile(settings, State.initial(config: settings),
               known_target_registry: registry,
               targeted_issue_ids_fn: fn limit ->
                 Inbox.drain_issue_ids(limit: limit, server: inbox)
               end,
               defer_targeted_issue_ids_fn: fn issue_ids, details ->
                 Inbox.defer_issue_ids(
                   issue_ids,
                   [server: inbox, max_defer_count: 0, now_ms: 1_000] ++ details
                 )
               end
             )

    assert Inbox.drain_issue_ids(limit: 10, server: inbox) == []

    assert %{
             "event" => "change_proposal_candidate_suspended",
             "issue_id" => "issue-known-suspended",
             "reason" => "source_route_pending",
             "source_workflow_profile" => "coding_pr_delivery",
             "source_workflow_profile_version" => 1,
             "source_workflow_route_key" => "developing"
           } = recent_event("change_proposal_candidate_suspended")
  end

  defp reconciliation_config do
    %Config{
      enabled?: true,
      candidate_discovery: :source_route_scan,
      source_routes: [route_ref(:review)],
      outcome_routes: %{
        ready: route_ref(:merging),
        changes_requested: route_ref(:rework),
        failed_checks: route_ref(:rework),
        already_merged: route_ref(:resolved)
      },
      require_approval?: true,
      require_passing_checks?: true,
      require_mergeable?: true,
      failed_checks_confirmation_count: 2
    }
  end

  defp maybe_route_ref(nil), do: nil
  defp maybe_route_ref(route_key), do: route_ref(route_key)

  defp route_ref(route_key) do
    %RouteRef{profile_kind: "coding_pr_delivery", profile_version: 1, route_key: route_key}
  end

  defp ready_facts do
    %Facts{
      provider_kind: "memory",
      repository: "acme/widgets",
      number: 35,
      url: "https://example.test/pr/35",
      branch: "feature/ready",
      head_sha: "abc123",
      provider_state: :open,
      review_summary: :approved,
      check_summary: :passing,
      mergeability_summary: :mergeable
    }
  end

  defp write_memory_reconciliation_workflow!(issues, overrides \\ []) do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      tracker_provider: %{
        "persist_state_updates" => true,
        "issues" => issues
      },
      tracker_active_states: Keyword.get(overrides, :tracker_active_states, ["Todo", "In Progress", "Merging", "Rework"]),
      tracker_terminal_states: ["Done", "Canceled"],
      tracker_state_phase_map: %{
        "Todo" => "todo",
        "In Progress" => "in_progress",
        "In Review" => "human_review",
        "Merging" => "merging",
        "Rework" => "rework",
        "Done" => "done",
        "Canceled" => "canceled"
      },
      tracker_raw_state_by_route_key: %{
        "planning" => "Todo",
        "developing" => "In Progress",
        "review" => "In Review",
        "merging" => "Merging",
        "rework" => "Rework",
        "resolved" => "Done",
        "rejected" => "Canceled"
      },
      tracker_policy_by_route_key: Keyword.get(overrides, :tracker_policy_by_route_key, nil),
      repo_provider_kind: "memory",
      repo_provider_repository: "acme/widgets",
      workflow_reconciliation: %{
        "change_proposal" =>
          Map.merge(
            default_change_proposal_reconciliation_config(),
            Keyword.get(overrides, :change_proposal_reconciliation, %{}),
            fn _key, default_value, override_value ->
              deep_merge(default_value, override_value)
            end
          )
      }
    )
  end

  defp default_change_proposal_reconciliation_config do
    %{
      "enabled" => true,
      "candidates" => %{
        "source_routes" => ["review"],
        "max_processed_issues_per_cycle" => 25
      },
      "gates" => %{
        "approval_required" => true,
        "passing_checks_required" => true,
        "mergeable_required" => true
      },
      "outcome_routes" => %{
        "ready" => "merging",
        "changes_requested" => "rework",
        "failed_checks" => "rework",
        "already_merged" => "resolved"
      },
      "thresholds" => %{
        "failed_checks_confirmation_count" => 2
      }
    }
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp tracker_tool_context(tool_name, workflow_capability) do
    %{
      "tool_metadata" => %{
        tool_name => %{
          "capability" => workflow_capability
        }
      }
    }
  end

  defp memory_issue(attrs) when is_map(attrs) do
    Map.merge(
      %{
        "description" => "",
        "priority" => 0,
        "labels" => []
      },
      attrs
    )
  end

  defp put_ready_repo_provider_payloads do
    Application.put_env(:symphony_elixir, :memory_repo_provider_pr, %{
      "number" => 35,
      "url" => "https://example.test/acme/widgets/-/pulls/35",
      "state" => "OPEN",
      "headRefName" => "feature/ready",
      "headRefOid" => "abc123",
      "mergeable" => "MERGEABLE",
      "mergeStateStatus" => "CLEAN"
    })

    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [])
    Application.put_env(:symphony_elixir, :memory_repo_provider_review_comments, [])

    Application.put_env(:symphony_elixir, :memory_repo_provider_reviews, [
      %{
        "state" => "APPROVED",
        "user" => %{"login" => "reviewer"},
        "submitted_at" => "2026-05-12T00:00:00Z"
      }
    ])

    Application.put_env(:symphony_elixir, :memory_repo_change_proposal_checks, [
      %{"name" => "ci", "status" => "completed", "conclusion" => "success"}
    ])
  end

  defp known_target_attrs(issue_id) when is_binary(issue_id) do
    %{
      "issue_id" => issue_id,
      "tracker_kind" => "memory",
      "repo_provider_kind" => "memory",
      "repository" => "acme/widgets",
      "number" => issue_id |> String.replace("issue-", "") |> Kernel.<>("-35")
    }
  end

  defp reconcile(settings, runtime_input, opts \\ []) when is_map(settings) and is_map(runtime_input) and is_list(opts) do
    runtime = RuntimeProjection.new(runtime_input)
    result = Reconciliation.reconcile_runtime(settings, RuntimeInput.from_projection(runtime, CodingPrDelivery.id()), opts)

    put_extension_state(runtime_input, result.extension_state)
  end

  defp put_extension_state(runtime_input, extension_state) when is_map(runtime_input) and is_map(extension_state) do
    workflow_extensions =
      runtime_input
      |> Map.get(:workflow_extensions, %{})
      |> case do
        extensions when is_map(extensions) -> extensions
        _extensions -> %{}
      end

    Map.put(runtime_input, :workflow_extensions, Map.put(workflow_extensions, CodingPrDelivery.id(), extension_state))
  end

  defp registry_issue_ids(registry) do
    registry
    |> then(&KnownTarget.Registry.list_targets(server: &1))
    |> Enum.map(& &1.issue_id)
  end

  defp workflow_scope(name) when is_binary(name) do
    %{
      "profile_kind" => "coding_pr_delivery",
      "profile_version" => 1,
      "scope_source" => "test",
      "test_scope" => name
    }
  end

  defp noop_command_handler, do: fn _command -> :ok end

  defp blocked_resource_command_handler(registry) do
    fn
      %RuntimeCommand{
        type: :release_blocked_resource,
        payload: %{resource_kind: resource_kind, resource_id: resource_id, reason: reason}
      } ->
        BlockedResourceRegistry.release(resource_kind, resource_id, reason, server: registry)

      command ->
        {:error, {:unexpected_runtime_command, command}}
    end
  end

  defp recent_issue_event(issue_id, event_name) when is_binary(issue_id) and is_binary(event_name) do
    %{issue_id: issue_id}
    |> EventStore.recent_issue_events(limit: 50)
    |> Enum.find(fn event -> event["event"] == event_name end)
    |> case do
      nil -> flunk("expected #{event_name} for #{issue_id}")
      event -> event
    end
  end

  defp tracker_tool_result_ignored_event(tool_name) when is_binary(tool_name) do
    EventStore.recent_events(limit: 50)
    |> Enum.find(fn event ->
      event["event"] == "change_proposal_tracker_tool_result_ignored" and
        event["dynamic_tool_name"] == tool_name
    end)
  end

  defp record_coding_pr_delivery_tool_result(tracker, tool, arguments, result, opts) do
    ToolResultRecorder.record_tool_result(:tracker, tracker, tool, arguments, result, opts)
  end

  defp recent_event(event_name) when is_binary(event_name) do
    EventStore.recent_events(limit: 50)
    |> Enum.find(fn event -> event["event"] == event_name end)
    |> case do
      nil -> flunk("expected #{event_name}")
      event -> event
    end
  end
end
