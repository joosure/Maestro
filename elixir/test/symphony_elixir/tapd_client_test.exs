defmodule SymphonyElixir.TapdClientTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Tracker.Error, as: TrackerError
  alias SymphonyElixir.Tracker.Tapd.{Adapter, Client, CommentCodec}

  test "fetch_candidate_issues returns an invalid configuration error when active states are missing" do
    tracker = %SymphonyElixir.Tracker.Config{
      kind: "tapd",
      endpoint: "https://api.tapd.cn",
      auth: %{},
      provider: %{"platform" => %{"workspace_id" => "53000000"}},
      lifecycle: %{}
    }

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_candidate_issues,
              code: :invalid_configuration,
              message: "TAPD active states are required.",
              details: %{source_reason: :missing_tapd_active_states}
            }} = Client.fetch_candidate_issues(tracker)
  end

  test "healthcheck lets the TAPD request layer inject workspace id" do
    tracker = tapd_tracker([])

    request_fun = fn request ->
      assert request.method == "GET"
      assert request.url == "https://api.tapd.cn/quickstart/testauth"
      assert request.params["workspace_id"] == "53000000"

      {:ok, %{status: 200, body: %{"status" => 1, "data" => %{"ok" => true}}}}
    end

    assert :ok = Adapter.healthcheck(tracker, request_fun: request_fun)
  end

  test "fetch_candidate_issues can be narrowed to configured candidate issue ids" do
    tracker =
      tapd_tracker(
        provider: %{
          "candidate_issue_ids" => ["story-2", "", "story-1", "story-2"]
        }
      )

    test_pid = self()

    assert {:ok, issues} =
             Client.fetch_candidate_issues(tracker,
               request_fun: fn
                 %{url: "https://api.tapd.cn/stories", params: %{"id" => story_id}} = request ->
                   send(test_pid, {:tapd_request, request})

                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => story_id,
                              "name" => "Story #{story_id}",
                              "status" => "merging",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/stories/get_time_relative_stories",
                   params: %{"story_id" => _story_id}
                 } = request ->
                   send(test_pid, {:tapd_request, request})
                   {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
               end
             )

    assert Enum.map(issues, & &1.id) == ["story-2", "story-1"]

    assert_receive {:tapd_request, %{url: "https://api.tapd.cn/stories", params: %{"id" => "story-2"}}}
    assert_receive {:tapd_request, %{url: "https://api.tapd.cn/stories", params: %{"id" => "story-1"}}}
    refute_received {:tapd_request, %{url: "https://api.tapd.cn/stories", params: %{"status" => _status}}}
  end

  test "fetch_stories_by_status allows multiple workitem types when terminal states match config" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])
    test_pid = self()

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["planning", "developing"],
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 workflow_matching_response(request)
               end
             )

    assert Enum.map(issues, & &1.id) == ["story-1", "story-2"]

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/stories",
                       params: %{"status" => "planning|developing"}
                     }}

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "story",
                         "system" => "story"
                       }
                     }}

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "feature",
                         "system" => "story"
                       }
                     }}
  end

  test "fetch_stories_by_status fails fast when active workitem types have terminal-state mismatches" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_issues_by_states,
              code: :tapd_mismatched_workitem_type_ids,
              details: %{
                details: %{
                  workitem_type_ids: ["story", "feature"],
                  mismatched_workitem_type_ids: ["feature"],
                  configured_terminal_states_by_type: configured_terminal_states_by_type,
                  terminal_states_by_type: terminal_states_by_type
                }
              }
            }} =
             Client.fetch_stories_by_status(["planning", "developing"],
               tracker: tracker,
               request_fun: &workflow_mismatch_response/1
             )

    assert Enum.sort(configured_terminal_states_by_type["story"]) == ["rejected", "resolved"]
    assert Enum.sort(configured_terminal_states_by_type["feature"]) == ["rejected", "resolved"]
    assert Enum.sort(terminal_states_by_type["story"]) == ["rejected", "resolved"]
    assert terminal_states_by_type["feature"] == ["done"]
  end

  test "fetch_stories_by_status applies configured workitem_type_id as a narrowing override" do
    tracker =
      tapd_tracker(
        terminal_states: ["resolved", "rejected"],
        platform: %{"workspace_id" => "53000000", "workitem_type_id" => "story"}
      )

    test_pid = self()

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["planning", "developing"],
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 workflow_matching_response(request)
               end
             )

    assert Enum.map(issues, & &1.id) == ["story-1"]

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/stories",
                       params: %{
                         "status" => "planning|developing",
                         "workitem_type_id" => "story"
                       }
                     }}

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "story",
                         "system" => "story"
                       }
                     }}

    refute_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "feature",
                         "system" => "story"
                       }
                     }}
  end

  test "fetch_stories_by_status applies configured workitem_type_ids as a shared workflow whitelist" do
    tracker =
      tapd_tracker(
        terminal_states: ["resolved", "rejected"],
        platform: %{"workspace_id" => "53000000", "workitem_type_ids" => ["story", "feature"]}
      )

    test_pid = self()

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["planning", "developing"],
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 workflow_whitelist_response(request)
               end
             )

    assert Enum.map(issues, & &1.id) == ["story-1", "story-2"]

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/stories",
                       params: %{"status" => "planning|developing"}
                     }}

    refute_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/stories",
                       params: %{"workitem_type_id" => _workitem_type_id}
                     }}

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "story",
                         "system" => "story"
                       }
                     }}

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "feature",
                         "system" => "story"
                       }
                     }}

    refute_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "ignored",
                         "system" => "story"
                       }
                     }}
  end

  test "fetch_stories_by_status validates all configured workitem_type_ids even when some are not observed" do
    tracker =
      tapd_tracker(
        terminal_states: ["resolved", "rejected"],
        platform: %{"workspace_id" => "53000000", "workitem_type_ids" => ["story", "feature"]}
      )

    test_pid = self()

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_issues_by_states,
              code: :tapd_mismatched_workitem_type_ids,
              details: %{
                details: %{
                  workitem_type_ids: ["story", "feature"],
                  mismatched_workitem_type_ids: ["feature"],
                  configured_terminal_states_by_type: configured_terminal_states_by_type,
                  terminal_states_by_type: terminal_states_by_type
                }
              }
            }} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 configured_scope_unobserved_type_mismatch_response(request)
               end
             )

    assert Enum.sort(configured_terminal_states_by_type["story"]) == ["rejected", "resolved"]
    assert Enum.sort(configured_terminal_states_by_type["feature"]) == ["rejected", "resolved"]
    assert Enum.sort(terminal_states_by_type["story"]) == ["rejected", "resolved"]
    assert terminal_states_by_type["feature"] == ["done"]

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "story",
                         "system" => "story"
                       }
                     }}

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "feature",
                         "system" => "story"
                       }
                     }}
  end

  test "fetch_stories_by_status narrows TAPD requests when workitem_type_ids contains one entry" do
    tracker =
      tapd_tracker(
        terminal_states: ["resolved", "rejected"],
        platform: %{"workspace_id" => "53000000", "workitem_type_ids" => ["story"]}
      )

    test_pid = self()

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["planning", "developing"],
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 workflow_matching_response(request)
               end
             )

    assert Enum.map(issues, & &1.id) == ["story-1"]

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/stories",
                       params: %{
                         "status" => "planning|developing",
                         "workitem_type_id" => "story"
                       }
                     }}
  end

  test "fetch_stories_by_status supports workflows_by_type with distinct terminal states" do
    tracker =
      tapd_tracker(
        active_states: ["planning", "coding"],
        terminal_states: ["resolved", "done"],
        state_phase_map: %{
          "planning" => "todo",
          "coding" => "in_progress",
          "resolved" => "done",
          "done" => "done"
        },
        workflows_by_type: %{
          "story" => %{
            "active_states" => ["planning", "developing", "merging", "rework"],
            "terminal_states" => ["resolved", "rejected"],
            "state_phase_map" => %{
              "planning" => "todo",
              "developing" => "in_progress",
              "review" => "human_review",
              "merging" => "merging",
              "rework" => "rework",
              "resolved" => "done",
              "rejected" => "canceled"
            },
            "raw_state_by_route_key" => %{
              "planning" => "planning",
              "developing" => "developing",
              "review" => "review",
              "merging" => "merging",
              "rework" => "rework",
              "resolved" => "resolved",
              "rejected" => "rejected"
            }
          },
          "feature" => %{
            "active_states" => ["queued", "coding", "shipping", "fixback"],
            "terminal_states" => ["done", "canceled"],
            "state_phase_map" => %{
              "queued" => "todo",
              "coding" => "in_progress",
              "qa_review" => "human_review",
              "shipping" => "merging",
              "fixback" => "rework",
              "done" => "done",
              "canceled" => "canceled"
            },
            "raw_state_by_route_key" => %{
              "planning" => "queued",
              "developing" => "coding",
              "review" => "qa_review",
              "merging" => "shipping",
              "rework" => "fixback",
              "resolved" => "done",
              "rejected" => "canceled"
            }
          }
        },
        platform: %{"workspace_id" => "53000000"}
      )

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["planning", "coding"],
               tracker: tracker,
               request_fun: &workflow_by_type_response/1
             )

    assert Enum.map(issues, &{&1.id, &1.workitem_type_id, &1.lifecycle_phase}) == [
             {"story-1", "story", "todo"},
             {"feature-1", "feature", "in_progress"}
           ]

    assert Enum.map(issues, & &1.workflow.raw_state_by_route_key.review) == ["review", "qa_review"]
  end

  test "fetch_stories_by_status applies global raw_state_by_route_key defaults and preserves per-type overrides" do
    tracker =
      tapd_tracker(
        active_states: ["status_4", "coding", "shipping", "fixback"],
        terminal_states: ["resolved", "done", "canceled"],
        state_phase_map: %{
          "status_4" => "todo",
          "coding" => "in_progress",
          "status_5" => "human_review",
          "qa_review" => "human_review",
          "shipping" => "merging",
          "fixback" => "rework",
          "done" => "done",
          "resolved" => "done",
          "canceled" => "canceled"
        },
        raw_state_by_route_key: %{
          "planning" => "status_4",
          "developing" => "coding",
          "review" => "status_5",
          "merging" => "shipping",
          "rework" => "fixback",
          "resolved" => "resolved",
          "rejected" => "canceled"
        },
        workflows_by_type: %{
          "story" => %{
            "active_states" => ["status_4", "coding", "shipping", "fixback"],
            "terminal_states" => ["resolved", "canceled"],
            "state_phase_map" => %{
              "status_4" => "todo",
              "coding" => "in_progress",
              "status_5" => "human_review",
              "shipping" => "merging",
              "fixback" => "rework",
              "resolved" => "done",
              "canceled" => "canceled"
            }
          },
          "feature" => %{
            "active_states" => ["status_4", "coding", "shipping", "fixback"],
            "terminal_states" => ["done", "canceled"],
            "state_phase_map" => %{
              "status_4" => "todo",
              "coding" => "in_progress",
              "qa_review" => "human_review",
              "shipping" => "merging",
              "fixback" => "rework",
              "done" => "done",
              "canceled" => "canceled"
            },
            "raw_state_by_route_key" => %{
              "review" => "qa_review",
              "resolved" => "done"
            }
          }
        },
        platform: %{"workspace_id" => "53000000"}
      )

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["status_4", "coding"],
               tracker: tracker,
               request_fun: &workflow_matching_with_global_route_response/1
             )

    assert Enum.map(issues, &{&1.id, &1.workflow.raw_state_by_route_key.planning, &1.workflow.raw_state_by_route_key.review}) == [
             {"story-1", "status_4", "status_5"},
             {"feature-1", "status_4", "qa_review"}
           ]

    assert Enum.map(issues, &{&1.id, &1.workflow.policy_by_route_key.planning, &1.workflow.policy_by_route_key.merging}) == [
             {"story-1", %{action: :transition_then_dispatch, transition_target: :developing}, %{action: :dispatch, execution_profile: "land"}},
             {"feature-1", %{action: :transition_then_dispatch, transition_target: :developing}, %{action: :dispatch, execution_profile: "land"}}
           ]
  end

  test "fetch_stories_by_status preserves per-type route_policy overrides while inheriting global defaults" do
    tracker =
      tapd_tracker(
        active_states: ["status_4", "coding", "shipping", "fixback"],
        terminal_states: ["resolved", "done", "canceled"],
        state_phase_map: %{
          "status_4" => "todo",
          "coding" => "in_progress",
          "status_5" => "human_review",
          "qa_review" => "human_review",
          "shipping" => "merging",
          "fixback" => "rework",
          "done" => "done",
          "resolved" => "done",
          "canceled" => "canceled"
        },
        raw_state_by_route_key: %{
          "planning" => "status_4",
          "developing" => "coding",
          "review" => "status_5",
          "merging" => "shipping",
          "rework" => "fixback",
          "resolved" => "resolved",
          "rejected" => "canceled"
        },
        policy_by_route_key: %{
          "planning" => %{"action" => "transition_then_dispatch", "transition_target" => "developing"},
          "merging" => %{"action" => "dispatch", "execution_profile" => "land"}
        },
        workflows_by_type: %{
          "story" => %{
            "active_states" => ["status_4", "coding", "shipping", "fixback"],
            "terminal_states" => ["resolved", "canceled"],
            "state_phase_map" => %{
              "status_4" => "todo",
              "coding" => "in_progress",
              "status_5" => "human_review",
              "shipping" => "merging",
              "fixback" => "rework",
              "resolved" => "done",
              "canceled" => "canceled"
            }
          },
          "feature" => %{
            "active_states" => ["status_4", "coding", "shipping", "fixback"],
            "terminal_states" => ["done", "canceled"],
            "state_phase_map" => %{
              "status_4" => "todo",
              "coding" => "in_progress",
              "qa_review" => "human_review",
              "shipping" => "merging",
              "fixback" => "rework",
              "done" => "done",
              "canceled" => "canceled"
            },
            "raw_state_by_route_key" => %{
              "review" => "qa_review",
              "resolved" => "done"
            },
            "policy_by_route_key" => %{
              "planning" => %{"action" => "transition", "transition_target" => "review"},
              "merging" => %{"execution_profile" => "ship"}
            }
          }
        },
        platform: %{"workspace_id" => "53000000"}
      )

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["status_4", "coding"],
               tracker: tracker,
               request_fun: &workflow_matching_with_global_route_response/1
             )

    assert Enum.map(issues, &{&1.id, &1.workflow.policy_by_route_key.planning, &1.workflow.policy_by_route_key.merging}) == [
             {"story-1", %{action: :transition_then_dispatch, transition_target: :developing}, %{action: :dispatch, execution_profile: "land"}},
             {"feature-1", %{action: :transition, transition_target: :review}, %{action: :dispatch, execution_profile: "ship"}}
           ]
  end

  test "fetch_stories_by_status validates workitem type terminal-state coverage across paginated workspace scans" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])
    test_pid = self()

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_issues_by_states,
              code: :tapd_mismatched_workitem_type_ids,
              details: %{
                details: %{
                  workitem_type_ids: ["story", "feature"],
                  mismatched_workitem_type_ids: ["feature"],
                  configured_terminal_states_by_type: configured_terminal_states_by_type,
                  terminal_states_by_type: terminal_states_by_type
                }
              }
            }} =
             Client.fetch_stories_by_status(["planning", "developing"],
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 paginated_workflow_mismatch_response(request)
               end
             )

    assert Enum.sort(configured_terminal_states_by_type["story"]) == ["rejected", "resolved"]
    assert Enum.sort(configured_terminal_states_by_type["feature"]) == ["rejected", "resolved"]
    assert Enum.sort(terminal_states_by_type["story"]) == ["rejected", "resolved"]
    assert terminal_states_by_type["feature"] == ["done"]

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/stories",
                       params: %{"status" => "planning|developing", "page" => 1, "limit" => 100}
                     }}

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/stories",
                       params: %{"status" => "planning|developing", "page" => 2, "limit" => 100}
                     }}
  end

  test "fetch_stories_by_status validates a single observed workitem type without narrowing override" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_issues_by_states,
              code: :tapd_mismatched_workitem_type_ids,
              details: %{
                details: %{
                  workitem_type_ids: ["feature"],
                  mismatched_workitem_type_ids: ["feature"],
                  configured_terminal_states_by_type: configured_terminal_states_by_type,
                  terminal_states_by_type: terminal_states_by_type
                }
              }
            }} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: &single_type_mismatch_response/1
             )

    assert Enum.sort(configured_terminal_states_by_type["feature"]) == ["rejected", "resolved"]
    assert terminal_states_by_type["feature"] == ["done"]
  end

  test "fetch_stories_by_status returns a structured error for malformed workflow terminal payloads" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_issues_by_states,
              code: :workflow_lookup_failed,
              details: %{
                workitem_type_id: "story",
                workflow_type: "status",
                nested_error: %TrackerError{
                  code: :invalid_response,
                  details: %{path: "/workflows/last_steps", body: body}
                }
              }
            }} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: &malformed_last_steps_response/1
             )

    assert body == %{
             "status" => 1,
             "data" => [
               %{"WorkflowStep" => %{"status" => %{"bad" => "value"}}}
             ]
           }
  end

  test "fetch_stories_by_status fails fast when configured workitem type exposes parallel end steps" do
    tracker =
      tapd_tracker(
        terminal_states: ["resolved", "rejected"],
        platform: %{"workspace_id" => "53000000", "workitem_type_id" => "story"}
      )

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_issues_by_states,
              code: :tapd_parallel_workitem_workflow,
              details: %{details: %{workitem_type_ids: ["story"], parallel_workitem_type_ids: ["story"]}}
            }} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: &parallel_workflow_response/1
             )
  end

  test "fetch_stories_by_status validates a single parallel workflow without narrowing override" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :fetch_issues_by_states,
              code: :tapd_parallel_workitem_workflow,
              details: %{details: %{workitem_type_ids: ["story"], parallel_workitem_type_ids: ["story"]}}
            }} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: &parallel_workflow_response/1
             )
  end

  test "fetch_stories_by_status auto-discovers and validates only observed workitem types" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])
    test_pid = self()

    assert {:ok, issues} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 auto_discovery_single_type_response(request)
               end
             )

    assert Enum.map(issues, & &1.id) == ["story-1"]

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "story",
                         "system" => "story"
                       }
                     }}

    refute_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/workflows/last_steps",
                       params: %{
                         "type" => "status",
                         "workitem_type_id" => "feature",
                         "system" => "story"
                       }
                     }}
  end

  test "fetch_stories_by_ids deduplicates ids and keeps single-id request semantics" do
    tracker = tapd_tracker([])
    test_pid = self()

    assert {:ok, issues} =
             Client.fetch_stories_by_ids(["story-2", "story-1", "story-2"],
               tracker: tracker,
               request_fun: fn
                 %{url: "https://api.tapd.cn/stories", params: %{"id" => story_id}} = request ->
                   send(test_pid, {:tapd_request, request})

                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => story_id,
                              "name" => "Story #{story_id}",
                              "status" => "planning",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/stories/get_time_relative_stories",
                   params: %{"story_id" => _story_id}
                 } = request ->
                   send(test_pid, {:tapd_request, request})
                   {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
               end
             )

    assert Enum.map(issues, & &1.id) == ["story-2", "story-1"]

    assert_receive {:tapd_request, %{url: "https://api.tapd.cn/stories", params: %{"id" => first_id}}}

    assert_receive {:tapd_request, %{url: "https://api.tapd.cn/stories", params: %{"id" => second_id}}}

    assert Enum.sort([first_id, second_id]) == ["story-1", "story-2"]
    refute String.contains?(first_id, ",")
    refute String.contains?(second_id, ",")
  end

  test "fetch_stories_by_status enriches blocked_by from incoming TAPD time relations" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])

    assert {:ok, [%{id: "story-1", blocked_by: blockers}]} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: fn
                 %{
                   url: "https://api.tapd.cn/stories",
                   params: %{"status" => "planning", "page" => 1, "limit" => 100}
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => "story-1",
                              "name" => "Story 1",
                              "status" => "planning",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/workflows/last_steps",
                   params: %{
                     "type" => "status",
                     "workitem_type_id" => "story",
                     "system" => "story"
                   }
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => %{"resolved" => "Resolved", "rejected" => "Rejected"}
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/workflows/last_steps",
                   params: %{"type" => "step", "workitem_type_id" => "story", "system" => "story"}
                 } ->
                   {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}

                 %{
                   url: "https://api.tapd.cn/stories/get_time_relative_stories",
                   params: %{"story_id" => "story-1"}
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "WorkitemTimeRelation" => %{
                              "workitem_id" => "blocker-1",
                              "dst_workitem_id" => "story-1",
                              "src_field" => "due",
                              "dst_field" => "begin",
                              "relation_type" => "after"
                            }
                          },
                          %{
                            "WorkitemTimeRelation" => %{
                              "workitem_id" => "story-1",
                              "dst_workitem_id" => "dependent-1",
                              "src_field" => "due",
                              "dst_field" => "begin",
                              "relation_type" => "after"
                            }
                          }
                        ]
                      }
                    }}

                 %{url: "https://api.tapd.cn/stories", params: %{"id" => "blocker-1"}} ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => "blocker-1",
                              "name" => "Blocker 1",
                              "status" => "developing",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}
               end
             )

    assert blockers == [
             %{
               id: "blocker-1",
               identifier: "TAPD-blocker-1",
               state: "developing",
               lifecycle_phase: "in_progress"
             }
           ]
  end

  test "fetch_stories_by_status uses empty blockers when time relations are unavailable" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])

    assert {:ok, [%{id: "story-1", blocked_by: []}]} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: fn
                 %{
                   url: "https://api.tapd.cn/stories",
                   params: %{"status" => "planning", "page" => 1, "limit" => 100}
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => "story-1",
                              "name" => "Story 1",
                              "status" => "planning",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/workflows/last_steps",
                   params: %{
                     "type" => "status",
                     "workitem_type_id" => "story",
                     "system" => "story"
                   }
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => %{"resolved" => "Resolved", "rejected" => "Rejected"}
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/workflows/last_steps",
                   params: %{"type" => "step", "workitem_type_id" => "story", "system" => "story"}
                 } ->
                   {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}

                 %{
                   url: "https://api.tapd.cn/stories/get_time_relative_stories",
                   params: %{"story_id" => "story-1"}
                 } ->
                   {:ok, %{status: 404, body: %{"status" => 0, "info" => "not enabled"}}}
               end
             )
  end

  test "fetch_stories_by_status keeps relation blockers when blocker state enrichment fails" do
    tracker = tapd_tracker(terminal_states: ["resolved", "rejected"])

    assert {:ok, [%{id: "story-1", blocked_by: blockers}]} =
             Client.fetch_stories_by_status(["planning"],
               tracker: tracker,
               request_fun: fn
                 %{
                   url: "https://api.tapd.cn/stories",
                   params: %{"status" => "planning", "page" => 1, "limit" => 100}
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => "story-1",
                              "name" => "Story 1",
                              "status" => "planning",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/workflows/last_steps",
                   params: %{
                     "type" => "status",
                     "workitem_type_id" => "story",
                     "system" => "story"
                   }
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => %{"resolved" => "Resolved", "rejected" => "Rejected"}
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/workflows/last_steps",
                   params: %{"type" => "step", "workitem_type_id" => "story", "system" => "story"}
                 } ->
                   {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}

                 %{
                   url: "https://api.tapd.cn/stories/get_time_relative_stories",
                   params: %{"story_id" => "story-1"}
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "WorkitemTimeRelation" => %{
                              "workitem_id" => "blocker-1",
                              "dst_workitem_id" => "story-1",
                              "src_field" => "due",
                              "dst_field" => "begin"
                            }
                          },
                          %{
                            "WorkitemTimeRelation" => %{
                              "workitem_id" => "blocker-2",
                              "dst_workitem_id" => "story-1",
                              "src_field" => "due",
                              "dst_field" => "begin"
                            }
                          }
                        ]
                      }
                    }}

                 %{url: "https://api.tapd.cn/stories", params: %{"id" => "blocker-1"}} ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => "blocker-1",
                              "name" => "Blocker 1",
                              "status" => "developing",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}

                 %{url: "https://api.tapd.cn/stories", params: %{"id" => "blocker-2"}} ->
                   {:ok, %{status: 404, body: %{"status" => 0, "info" => "story not found"}}}
               end
             )

    assert blockers == [
             %{
               id: "blocker-1",
               identifier: "TAPD-blocker-1",
               state: "developing",
               lifecycle_phase: "in_progress"
             },
             %{id: "blocker-2", identifier: "TAPD-blocker-2", state: nil, lifecycle_phase: nil}
           ]
  end

  test "fetch_stories_by_ids enriches blocked_by from TAPD time relations during refresh" do
    tracker = tapd_tracker([])

    assert {:ok, [%{id: "story-1", blocked_by: blockers}]} =
             Client.fetch_stories_by_ids(["story-1"],
               tracker: tracker,
               request_fun: fn
                 %{url: "https://api.tapd.cn/stories", params: %{"id" => "story-1"}} ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => "story-1",
                              "name" => "Story 1",
                              "status" => "planning",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}

                 %{
                   url: "https://api.tapd.cn/stories/get_time_relative_stories",
                   params: %{"story_id" => "story-1"}
                 } ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "WorkitemTimeRelation" => %{
                              "workitem_id" => "blocker-2",
                              "dst_workitem_id" => "story-1",
                              "src_field" => "begin",
                              "dst_field" => "begin",
                              "relation_type" => "after"
                            }
                          }
                        ]
                      }
                    }}

                 %{url: "https://api.tapd.cn/stories", params: %{"id" => "blocker-2"}} ->
                   {:ok,
                    %{
                      status: 200,
                      body: %{
                        "status" => 1,
                        "data" => [
                          %{
                            "Story" => %{
                              "id" => "blocker-2",
                              "name" => "Blocker 2",
                              "status" => "resolved",
                              "workitem_type_id" => "story"
                            }
                          }
                        ]
                      }
                    }}
               end
             )

    assert blockers == [
             %{
               id: "blocker-2",
               identifier: "TAPD-blocker-2",
               state: "resolved",
               lifecycle_phase: "done"
             }
           ]
  end

  test "update_story_status normalizes workflow business errors" do
    tracker = tapd_tracker([])

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :update_issue_state,
              code: :tapd_story_workflow_error,
              message: "status is invalid for current workflow",
              details: %{
                story_id: "story-1",
                target_status: "resolved",
                message: "status is invalid for current workflow",
                body: %{"info" => "status is invalid for current workflow", "status" => 0}
              }
            }} =
             Client.update_story_status("story-1", "resolved",
               tracker: tracker,
               request_fun: fn %{url: url, params: params} ->
                 assert url == "https://api.tapd.cn/stories"

                 assert params == %{
                          "id" => "story-1",
                          "status" => "resolved",
                          "workspace_id" => "53000000"
                        }

                 {:ok,
                  %{
                    status: 200,
                    body: %{"status" => 0, "info" => "status is invalid for current workflow"}
                  }}
               end
             )
  end

  test "update_story_status normalizes parallel workflow business errors" do
    tracker = tapd_tracker([])

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :update_issue_state,
              code: :tapd_story_parallel_workflow_error,
              message: "当前需求属于并行工作流，请先完成并行节点",
              details: %{
                story_id: "story-1",
                target_status: "resolved",
                message: "当前需求属于并行工作流，请先完成并行节点",
                body: %{"info" => "当前需求属于并行工作流，请先完成并行节点", "status" => 0}
              }
            }} =
             Client.update_story_status("story-1", "resolved",
               tracker: tracker,
               request_fun: fn _request ->
                 {:ok,
                  %{
                    status: 200,
                    body: %{"status" => 0, "info" => "当前需求属于并行工作流，请先完成并行节点"}
                  }}
               end
             )
  end

  test "request retries transient TAPD status responses before succeeding" do
    tracker = tapd_tracker([])
    test_pid = self()
    Process.put(:tapd_request_attempt, 0)

    assert {:ok, %{"status" => 1, "data" => [%{"Story" => %{"id" => "story-1"}}]}} =
             Client.request(
               "GET",
               "/stories",
               %{"id" => "story-1"},
               tracker: tracker,
               retry_delays_ms: [0, 0],
               sleep_fun: fn delay_ms ->
                 send(test_pid, {:tapd_sleep, delay_ms})
                 :ok
               end,
               request_fun: fn request ->
                 attempt = Process.get(:tapd_request_attempt, 0) + 1
                 Process.put(:tapd_request_attempt, attempt)
                 send(test_pid, {:tapd_request_attempt, attempt, request})

                 case attempt do
                   1 ->
                     {:ok, %{status: 429, body: "{\"error_msg\":\"Too Many Requests\"}\n"}}

                   2 ->
                     {:ok, %{status: 503, body: "{\"error_msg\":\"Service Unavailable\"}\n"}}

                   _ ->
                     {:ok,
                      %{
                        status: 200,
                        body: %{"status" => 1, "data" => [%{"Story" => %{"id" => "story-1"}}]}
                      }}
                 end
               end
             )

    assert_received {:tapd_request_attempt, 1, %{url: "https://api.tapd.cn/stories"}}
    assert_received {:tapd_request_attempt, 2, %{url: "https://api.tapd.cn/stories"}}
    assert_received {:tapd_request_attempt, 3, %{url: "https://api.tapd.cn/stories"}}
    assert_received {:tapd_sleep, 0}
    assert_received {:tapd_sleep, 0}
  end

  test "request returns the last transient TAPD status after exhausting retries" do
    tracker = tapd_tracker([])
    test_pid = self()
    Process.put(:tapd_request_attempt, 0)

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :request,
              code: :http_status,
              retryable?: true,
              details: %{status: 429, body: "{\"error_msg\":\"Too Many Requests\"}\n"}
            }} =
             Client.request(
               "GET",
               "/stories",
               %{"id" => "story-1"},
               tracker: tracker,
               retry_delays_ms: [0, 0],
               sleep_fun: fn delay_ms ->
                 send(test_pid, {:tapd_sleep, delay_ms})
                 :ok
               end,
               request_fun: fn request ->
                 attempt = Process.get(:tapd_request_attempt, 0) + 1
                 Process.put(:tapd_request_attempt, attempt)
                 send(test_pid, {:tapd_request_attempt, attempt, request})
                 {:ok, %{status: 429, body: "{\"error_msg\":\"Too Many Requests\"}\n"}}
               end
             )

    assert_received {:tapd_request_attempt, 1, %{url: "https://api.tapd.cn/stories"}}
    assert_received {:tapd_request_attempt, 2, %{url: "https://api.tapd.cn/stories"}}
    assert_received {:tapd_request_attempt, 3, %{url: "https://api.tapd.cn/stories"}}
    assert_received {:tapd_sleep, 0}
    assert_received {:tapd_sleep, 0}
  end

  test "request does not retry non-retryable TAPD status responses" do
    tracker = tapd_tracker([])
    test_pid = self()
    Process.put(:tapd_request_attempt, 0)

    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :request,
              code: :http_status,
              retryable?: false,
              details: %{status: 400, body: "{\"error_msg\":\"Bad Request\"}\n"}
            }} =
             Client.request(
               "GET",
               "/stories",
               %{"id" => "story-1"},
               tracker: tracker,
               retry_delays_ms: [0, 0],
               sleep_fun: fn delay_ms ->
                 send(test_pid, {:tapd_sleep, delay_ms})
                 :ok
               end,
               request_fun: fn request ->
                 attempt = Process.get(:tapd_request_attempt, 0) + 1
                 Process.put(:tapd_request_attempt, attempt)
                 send(test_pid, {:tapd_request_attempt, attempt, request})
                 {:ok, %{status: 400, body: "{\"error_msg\":\"Bad Request\"}\n"}}
               end
             )

    assert_received {:tapd_request_attempt, 1, %{url: "https://api.tapd.cn/stories"}}
    refute_received {:tapd_request_attempt, 2, _request}
    refute_received {:tapd_sleep, _delay_ms}
  end

  test "request renders markdown comment descriptions to TAPD HTML" do
    tracker = tapd_tracker([])
    test_pid = self()
    markdown = "### Plan\n- [x] Sync `pr_url: https://github.com/org/repo/pull/123`"

    assert {:ok, %{"status" => 1, "data" => %{}}} =
             Client.request(
               "POST",
               "/comments",
               %{"entry_id" => "story-1", "description" => markdown},
               tracker: tracker,
               request_fun: fn request ->
                 send(test_pid, {:tapd_request, request})
                 {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
               end
             )

    assert_received {:tapd_request,
                     %{
                       url: "https://api.tapd.cn/comments",
                       params: %{
                         "description" => encoded_description,
                         "entry_id" => "story-1",
                         "workspace_id" => "53000000"
                       }
                     }}

    assert encoded_description == CommentCodec.encode_description(markdown)
    assert encoded_description =~ "<h3>Plan</h3>"
    assert encoded_description =~ "<code>pr_url: https://github.com/org/repo/pull/123</code>"
  end

  test "request decodes TAPD comment html bodies back to markdown" do
    tracker = tapd_tracker([])

    html_description =
      CommentCodec.encode_description("### Plan\n- pr_url: https://github.com/org/repo/pull/123")

    assert {:ok, %{"status" => 1, "data" => [%{"Comment" => %{"description" => description}}]}} =
             Client.request(
               "GET",
               "/comments",
               %{"entry_type" => "stories", "entry_id" => "story-1"},
               tracker: tracker,
               request_fun: fn %{url: "https://api.tapd.cn/comments"} ->
                 {:ok,
                  %{
                    status: 200,
                    body: %{
                      "status" => 1,
                      "data" => [
                        %{
                          "Comment" => %{
                            "id" => "comment-1",
                            "description" => html_description
                          }
                        }
                      ]
                    }
                  }}
               end
             )

    assert description == "### Plan\n- pr_url: https://github.com/org/repo/pull/123"
  end

  defp tapd_tracker(overrides) do
    overrides = Enum.into(overrides, %{})

    %{
      kind: "tapd",
      endpoint: "https://api.tapd.cn",
      auth:
        Map.merge(
          %{
            "api_key" => "tapd-user",
            "api_secret" => "tapd-secret"
          },
          Map.get(overrides, :auth, %{})
        ),
      provider:
        Map.merge(
          %{
            "platform" => Map.get(overrides, :platform, %{"workspace_id" => "53000000"})
          },
          Map.get(overrides, :provider, %{})
        ),
      lifecycle:
        Map.merge(
          %{
            "active_states" => Map.get(overrides, :active_states, ["planning", "developing"]),
            "terminal_states" => Map.get(overrides, :terminal_states, ["resolved", "rejected"]),
            "state_phase_map" =>
              Map.get(overrides, :state_phase_map, %{
                "planning" => "todo",
                "developing" => "in_progress",
                "resolved" => "done",
                "rejected" => "canceled"
              }),
            "raw_state_by_route_key" => Map.get(overrides, :raw_state_by_route_key),
            "policy_by_route_key" => Map.get(overrides, :policy_by_route_key),
            "workflows_by_type" => Map.get(overrides, :workflows_by_type)
          },
          Map.get(overrides, :lifecycle, %{})
        )
    }
  end

  defp workflow_matching_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => [
           %{
             "Story" => %{
               "id" => "story-1",
               "name" => "Story 1",
               "status" => "planning",
               "workitem_type_id" => "story"
             }
           },
           %{
             "Story" => %{
               "id" => "story-2",
               "name" => "Story 2",
               "status" => "developing",
               "workitem_type_id" => "feature"
             }
           }
         ]
       }
     }}
  end

  defp workflow_matching_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{
           "type" => "status",
           "workitem_type_id" => workitem_type_id,
           "system" => "story"
         }
       })
       when workitem_type_id in ["story", "feature"] do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => %{"resolved" => "Resolved", "rejected" => "Rejected"}
       }
     }}
  end

  defp workflow_matching_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
       })
       when workitem_type_id in ["story", "feature"] do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
  end

  defp workflow_matching_response(%{
         url: "https://api.tapd.cn/stories/get_time_relative_stories",
         params: %{"story_id" => _story_id}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
  end

  defp workflow_whitelist_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => [
           %{
             "Story" => %{
               "id" => "story-1",
               "name" => "Story 1",
               "status" => "planning",
               "workitem_type_id" => "story"
             }
           },
           %{
             "Story" => %{
               "id" => "story-2",
               "name" => "Story 2",
               "status" => "developing",
               "workitem_type_id" => "feature"
             }
           },
           %{
             "Story" => %{
               "id" => "ignored-1",
               "name" => "Ignored 1",
               "status" => "planning",
               "workitem_type_id" => "ignored"
             }
           }
         ]
       }
     }}
  end

  defp workflow_whitelist_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{
           "type" => "status",
           "workitem_type_id" => workitem_type_id,
           "system" => "story"
         }
       })
       when workitem_type_id in ["story", "feature"] do
    workflow_matching_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "status", "workitem_type_id" => workitem_type_id, "system" => "story"}
    })
  end

  defp workflow_whitelist_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
       })
       when workitem_type_id in ["story", "feature"] do
    workflow_matching_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
    })
  end

  defp workflow_whitelist_response(%{
         url: "https://api.tapd.cn/stories/get_time_relative_stories",
         params: %{"story_id" => _story_id}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
  end

  defp workflow_by_type_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => [
           %{
             "Story" => %{
               "id" => "story-1",
               "name" => "Story 1",
               "status" => "planning",
               "workitem_type_id" => "story"
             }
           },
           %{
             "Story" => %{
               "id" => "feature-1",
               "name" => "Feature 1",
               "status" => "coding",
               "workitem_type_id" => "feature"
             }
           }
         ]
       }
     }}
  end

  defp workflow_by_type_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => %{"resolved" => "Resolved", "rejected" => "Rejected"}
       }
     }}
  end

  defp workflow_by_type_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "feature", "system" => "story"}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => %{"done" => "Done", "canceled" => "Canceled"}
       }
     }}
  end

  defp workflow_by_type_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
       })
       when workitem_type_id in ["story", "feature"] do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
  end

  defp workflow_by_type_response(%{
         url: "https://api.tapd.cn/stories/get_time_relative_stories",
         params: %{"story_id" => _story_id}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
  end

  defp workflow_matching_with_global_route_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => [
           %{
             "Story" => %{
               "id" => "story-1",
               "name" => "Story 1",
               "status" => "status_4",
               "workitem_type_id" => "story"
             }
           },
           %{
             "Story" => %{
               "id" => "feature-1",
               "name" => "Feature 1",
               "status" => "coding",
               "workitem_type_id" => "feature"
             }
           }
         ]
       }
     }}
  end

  defp workflow_matching_with_global_route_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => %{"resolved" => "Resolved", "canceled" => "Canceled"}
       }
     }}
  end

  defp workflow_matching_with_global_route_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "feature", "system" => "story"}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => %{"done" => "Done", "canceled" => "Canceled"}
       }
     }}
  end

  defp workflow_matching_with_global_route_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
       })
       when workitem_type_id in ["story", "feature"] do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
  end

  defp workflow_matching_with_global_route_response(%{
         url: "https://api.tapd.cn/stories/get_time_relative_stories",
         params: %{"story_id" => _story_id}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
  end

  defp workflow_mismatch_response(%{url: "https://api.tapd.cn/stories"}) do
    workflow_matching_response(%{url: "https://api.tapd.cn/stories"})
  end

  defp workflow_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
       }) do
    workflow_matching_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
    })
  end

  defp workflow_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "feature", "system" => "story"}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{"done" => "Done"}}}}
  end

  defp workflow_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
       })
       when workitem_type_id in ["story", "feature"] do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
  end

  defp configured_scope_unobserved_type_mismatch_response(%{
         url: "https://api.tapd.cn/stories"
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => story_entries("story", 1, "story", "planning")
       }
     }}
  end

  defp configured_scope_unobserved_type_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
       }) do
    workflow_matching_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
    })
  end

  defp configured_scope_unobserved_type_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "feature", "system" => "story"}
       }) do
    workflow_mismatch_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "status", "workitem_type_id" => "feature", "system" => "story"}
    })
  end

  defp configured_scope_unobserved_type_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
       })
       when workitem_type_id in ["story", "feature"] do
    workflow_matching_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "step", "workitem_type_id" => workitem_type_id, "system" => "story"}
    })
  end

  defp configured_scope_unobserved_type_mismatch_response(%{
         url: "https://api.tapd.cn/stories/get_time_relative_stories",
         params: %{"story_id" => _story_id}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
  end

  defp parallel_workflow_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => [
           %{
             "Story" => %{
               "id" => "story-1",
               "name" => "Story 1",
               "status" => "planning",
               "workitem_type_id" => "story"
             }
           }
         ]
       }
     }}
  end

  defp parallel_workflow_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => %{"resolved" => "Resolved", "rejected" => "Rejected"}
       }
     }}
  end

  defp parallel_workflow_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => "story", "system" => "story"}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => %{"step-1" => "QA review"}
       }
     }}
  end

  defp paginated_workflow_mismatch_response(%{
         url: "https://api.tapd.cn/stories",
         params: %{"page" => 1}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => story_entries("story", 100, "story", "planning")
       }
     }}
  end

  defp paginated_workflow_mismatch_response(%{
         url: "https://api.tapd.cn/stories",
         params: %{"page" => 2}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => story_entries("feature", 1, "feature", "developing")
       }
     }}
  end

  defp paginated_workflow_mismatch_response(request),
    do: workflow_mismatch_response(request)

  defp single_type_mismatch_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => story_entries("feature", 1, "feature", "planning")
       }
     }}
  end

  defp single_type_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "feature", "system" => "story"}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{"done" => "Done"}}}}
  end

  defp single_type_mismatch_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => "feature", "system" => "story"}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
  end

  defp auto_discovery_single_type_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => story_entries("story", 1, "story", "planning")
       }
     }}
  end

  defp auto_discovery_single_type_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
       }) do
    workflow_matching_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
    })
  end

  defp auto_discovery_single_type_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => "story", "system" => "story"}
       }) do
    workflow_matching_response(%{
      url: "https://api.tapd.cn/workflows/last_steps",
      params: %{"type" => "step", "workitem_type_id" => "story", "system" => "story"}
    })
  end

  defp auto_discovery_single_type_response(%{
         url: "https://api.tapd.cn/stories/get_time_relative_stories",
         params: %{"story_id" => _story_id}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => []}}}
  end

  defp malformed_last_steps_response(%{url: "https://api.tapd.cn/stories"}) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => story_entries("story", 1, "story", "planning")
       }
     }}
  end

  defp malformed_last_steps_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "status", "workitem_type_id" => "story", "system" => "story"}
       }) do
    {:ok,
     %{
       status: 200,
       body: %{
         "status" => 1,
         "data" => [
           %{"WorkflowStep" => %{"status" => %{"bad" => "value"}}}
         ]
       }
     }}
  end

  defp malformed_last_steps_response(%{
         url: "https://api.tapd.cn/workflows/last_steps",
         params: %{"type" => "step", "workitem_type_id" => "story", "system" => "story"}
       }) do
    {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
  end

  defp story_entries(prefix, count, workitem_type_id, status) do
    1..count
    |> Enum.map(fn index ->
      %{
        "Story" => %{
          "id" => "#{prefix}-#{index}",
          "name" => "#{String.capitalize(prefix)} #{index}",
          "status" => status,
          "workitem_type_id" => workitem_type_id
        }
      }
    end)
  end
end
