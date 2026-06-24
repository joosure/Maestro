defmodule SymphonyElixir.TapdAdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Bridge
  alias SymphonyElixir.Tracker.Error, as: TrackerError
  alias SymphonyElixir.Tracker.Tapd.{Adapter, CommentCodec, ToolExecutor, WorkflowConfig}
  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store, as: ReadinessStore

  test "tapd config validates required fields and advertises typed tracker tools only" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning", "developing"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert :ok = Config.validate!()
    assert SymphonyElixir.Tracker.adapter() == Adapter

    specs = DynamicTool.tool_specs(dynamic_tool_source: SymphonyElixir.Tracker.DynamicToolSource)
    names = Enum.map(specs, &Map.fetch!(&1, "name"))

    refute "tapd_api" in names
    assert "tapd_issue_snapshot" in names
    assert "tapd_move_issue" in names
    assert "tapd_upsert_workpad" in names
    assert "tapd_attach_external_reference" in names
    assert "tapd_upsert_comment" in names
    assert "tapd_create_follow_up_story" in names
    assert "tapd_read_story_relations" in names
    assert "tapd_add_story_relation" in names
    assert "tapd_read_story_dependencies" in names
    assert "tapd_save_story_dependency" in names
    assert "tapd_provider_diagnostics" in names

    assert MapSet.subset?(
             MapSet.new([
               "tracker.issue_snapshot",
               "tracker.move_issue",
               "tracker.upsert_workpad",
               "tracker.attach_external_reference",
               "tracker.upsert_comment",
               "tracker.create_follow_up_issue",
               "tracker.read_issue_relations",
               "tracker.add_issue_relation",
               "tracker.read_issue_dependencies",
               "tracker.save_issue_dependency",
               "tracker.provider_diagnostics"
             ]),
             MapSet.new(Adapter.capabilities())
           )

    assert %{
             "capability" => "tracker.provider_diagnostics",
             "sideEffect" => "read_only"
           } = Enum.find(ToolExecutor.tool_specs(), &(&1["name"] == "tapd_provider_diagnostics"))

    workpad_spec = Enum.find(ToolExecutor.tool_specs(), &(&1["name"] == "tapd_upsert_workpad"))

    assert get_in(workpad_spec, ["inputSchema", "required"]) == ["issue_id", "body"]

    refute Map.has_key?(get_in(workpad_spec, ["inputSchema", "properties"]), "sections")
  end

  test "tapd config validation rejects missing workspace_id and blank optional platform values" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{}
    )

    assert_validate_error(:missing_tapd_workspace_id, :missing_project_reference)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000", "workitem_type_id" => ""}
    )

    assert_validate_error(:invalid_tapd_workitem_type_id)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000", "workitem_type_ids" => []}
    )

    assert_validate_error(:invalid_tapd_workitem_type_ids)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000", "workitem_type_ids" => ["story", "  "]}
    )

    assert_validate_error(:invalid_tapd_workitem_type_ids)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000", "comment_author" => ""}
    )

    assert_validate_error(:invalid_tapd_comment_author)
  end

  test "tapd config validation accepts non-empty workitem_type_ids list" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning", "developing"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{
        "workspace_id" => "53000000",
        "workitem_type_ids" => ["1153070854001000001", "1153070854001000002"]
      }
    )

    assert :ok = Config.validate!()
  end

  test "tapd config validation accepts workflows_by_type without global state lists" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      tracker_state_phase_map: nil,
      tracker_workflows_by_type: %{
        "1153070854001000001" => %{
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
        }
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert :ok = Config.validate!()
  end

  test "tapd config validation accepts explicit global raw_state_by_route_key" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["status_4", "developing", "merging", "rework"],
      tracker_terminal_states: ["resolved", "rejected"],
      tracker_state_phase_map: %{
        "status_4" => "todo",
        "developing" => "in_progress",
        "status_5" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      tracker_raw_state_by_route_key: %{
        "planning" => "status_4",
        "developing" => "developing",
        "review" => "status_5",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "resolved",
        "rejected" => "rejected"
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert :ok = Config.validate!()
  end

  test "tapd config validation accepts explicit non-coding workflow profile route vocabulary" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_requirement_analysis_workflow_config([])
    )

    assert :ok = Config.validate!()

    workflow = WorkflowConfig.global_workflow(Config.settings!().tracker)

    assert workflow.profile.kind == "requirement_analysis"
    assert workflow.profile.version == 1
    assert workflow.raw_state_by_route_key.intake == "intake"

    assert workflow.policy_by_route_key.intake == %{
             action: :transition_then_dispatch,
             transition_target: :analyzing
           }

    refute Map.has_key?(workflow.raw_state_by_route_key, :planning)
  end

  test "tapd config validation rejects route keys outside the active workflow profile vocabulary" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_requirement_analysis_workflow_config(
        tracker_raw_state_by_route_key: %{
          "intake" => "intake",
          "analyzing" => "analyzing",
          "needs_info" => "needs_info",
          "review" => "review",
          "ready" => "ready",
          "rejected" => "rejected",
          "planning" => "intake"
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_raw_state_route_key, :global, invalid_requirement_analysis_route_key("planning")}})
  end

  test "tapd config validation rejects unsupported execution profiles for active workflow profile" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_requirement_analysis_workflow_config(
        tracker_policy_by_route_key: %{
          "analyzing" => %{"action" => "dispatch", "execution_profile" => "land"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:unsupported_route_policy_execution_profile, :global, requirement_analysis_route_ref(:analyzing), "land"}})
  end

  test "tapd config validation accepts explicit global policy_by_route_key" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{
            "action" => "transition_then_dispatch",
            "transition_target" => "developing"
          },
          "developing" => %{"action" => "dispatch"},
          "review" => %{"action" => "wait"},
          "merging" => %{"action" => "dispatch", "execution_profile" => "land"},
          "rework" => %{"action" => "dispatch"},
          "resolved" => %{"action" => "stop"},
          "rejected" => %{"action" => "stop"}
        }
      )
    )

    assert :ok = Config.validate!()
  end

  test "tapd config validation accepts explicit transition policy_by_route_key to non-dispatch review routes" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{"action" => "transition", "transition_target" => "review"}
        }
      )
    )

    assert :ok = Config.validate!()
  end

  test "tapd config validation rejects invalid explicit global raw_state_by_route_key" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["status_4", "developing", "merging", "rework"],
      tracker_terminal_states: ["resolved", "rejected"],
      tracker_state_phase_map: %{
        "status_4" => "human_review",
        "developing" => "in_progress",
        "status_5" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      tracker_raw_state_by_route_key: %{
        "planning" => "status_4",
        "developing" => "developing",
        "review" => "status_5",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "resolved",
        "rejected" => "rejected"
      },
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_raw_state_lifecycle_phase, :global, coding_route_ref(:planning), "status_4", "human_review", "todo"}})
  end

  test "tapd config validation rejects raw_state_by_route_key with non-canonical route keys" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_raw_state_by_route_key: %{
          "planning" => "status_4",
          "developing" => "developing",
          "review" => "status_5",
          "merging" => "merging",
          "rework" => "rework",
          "resolved" => "resolved",
          "rejected" => "rejected",
          "qa_review" => "status_5"
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_raw_state_route_key, :global, invalid_coding_route_key("qa_review")}})
  end

  test "tapd config validation rejects raw_state_by_route_key with blank raw tracker states" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_raw_state_by_route_key: %{
          "planning" => "status_4",
          "developing" => "developing",
          "review" => " ",
          "merging" => "merging",
          "rework" => "rework",
          "resolved" => "resolved",
          "rejected" => "rejected"
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_raw_state_by_route_key_value, :global, coding_route_ref(:review), " "}})
  end

  test "tapd config validation rejects invalid explicit global policy_by_route_key" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{"action" => "transition_then_dispatch", "transition_target" => "review"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_route_policy_transition_phase, :global, coding_route_ref(:planning), coding_route_ref(:review), "human_review"}})
  end

  test "tapd config validation rejects policy_by_route_key with missing transition_target" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "developing" => %{"action" => "transition"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:missing_route_policy_transition_target, :global, coding_route_ref(:developing)}})
  end

  test "tapd config validation rejects unknown policy_by_route_key fields" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "developing" => %{"action" => "dispatch", "unexpected_field" => "land"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:unsupported_route_policy_field, :global, coding_route_ref(:developing), "unexpected_field"}})
  end

  test "tapd config validation rejects transition_target on non-transition actions" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "developing" => %{"action" => "dispatch", "transition_target" => "review"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_route_policy_transition_target_action, :global, coding_route_ref(:developing), :dispatch}})
  end

  test "tapd config validation rejects policy_by_route_key with transition cycles" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{"action" => "transition", "transition_target" => "planning"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:route_policy_transition_target_cycle, :global, coding_route_ref(:planning), coding_route_ref(:planning)}})
  end

  test "tapd config validation rejects policy_by_route_key with raw-state transition targets" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{"action" => "transition", "transition_target" => "status_5"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_route_policy_transition_target_key, :global, coding_route_ref(:planning), invalid_coding_route_key("status_5")}})
  end

  test "tapd config validation rejects policy_by_route_key with invalid actions" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{"action" => "ship"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_route_policy_action, :global, coding_route_ref(:planning), nil}})
  end

  test "tapd config validation rejects policy_by_route_key with non-canonical keys" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "unknown_route" => %{"action" => "stop"}
        }
      )
    )

    assert_validate_error({:invalid_tapd_raw_state_by_route_key, {:invalid_route_policy_key, :global, invalid_coding_route_key("unknown_route")}})
  end

  test "tapd config validation rejects workflows_by_type policy_by_route_key with non-canonical keys" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_workflows_by_type: %{
          "feature" => %{
            "policy_by_route_key" => %{
              "unknown_route" => %{"action" => "stop"}
            }
          }
        }
      )
    )

    assert_validate_error({:invalid_tapd_workflows_by_type, "feature", {:invalid_route_policy_key, "feature", invalid_coding_route_key("unknown_route")}})
  end

  test "tapd config validation rejects workflows_by_type policy_by_route_key with unknown fields" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_workflows_by_type: %{
          "feature" => %{
            "policy_by_route_key" => %{
              "developing" => %{"action" => "dispatch", "unexpected_field" => "land"}
            }
          }
        }
      )
    )

    assert_validate_error({:invalid_tapd_workflows_by_type, "feature", {:unsupported_route_policy_field, "feature", coding_route_ref(:developing), "unexpected_field"}})
  end

  test "tapd config validation rejects workflows_by_type raw_state_by_route_key with non-canonical keys" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_workflows_by_type: %{
          "feature" => %{
            "raw_state_by_route_key" => %{
              "unknown_route" => "status_5"
            }
          }
        }
      )
    )

    assert_validate_error({:invalid_tapd_workflows_by_type, "feature", {:invalid_raw_state_route_key, "feature", invalid_coding_route_key("unknown_route")}})
  end

  test "tapd config validation rejects mixed workflows_by_type and explicit workitem scopes" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_state_phase_map: %{
        "planning" => "todo",
        "developing" => "in_progress",
        "review" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      tracker_workflows_by_type: %{
        "1153070854001000001" => %{
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
        }
      },
      tracker_platform: %{
        "workspace_id" => "53000000",
        "workitem_type_id" => "1153070854001000001"
      }
    )

    assert_validate_error(:conflicting_tapd_workitem_type_scope)
  end

  test "tapd config validation rejects blank active and terminal state lists" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["", "   "],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert_validate_error(:missing_tapd_active_states)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["", "   "],
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    assert_validate_error(:missing_tapd_terminal_states)
  end

  test "tapd_issue_snapshot returns typed story, workflow, comments, and workpad data" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())
    register_tapd_workpad!("1153000000000000001", "1153000000000000999")

    response =
      Bridge.execute(
        "tapd_issue_snapshot",
        %{
          "issue_id" => "TAPD-1153000000000000001"
        },
        request_fun: tapd_typed_tool_request_fun(self())
      )

    assert response["success"] == true, inspect(response)

    payload = response["payload"]

    assert get_in(payload, ["issue", "id"]) == "1153000000000000001"
    assert get_in(payload, ["issue", "identifier"]) == "TAPD-1153000000000000001"
    assert get_in(payload, ["issue", "state", "name"]) == "developing"
    assert get_in(payload, ["issue", "state", "type"]) == "in_progress"
    assert get_in(payload, ["issue", "workflow", "rawStateByRouteKey", "review"]) == "status_5"
    assert get_in(payload, ["workpad", "id"]) == "tapd:issue:1153000000000000001:workpad"
    assert get_in(payload, ["workpad", "provider_ref"]) == %{"type" => "comment", "id" => "1153000000000000999"}

    assert Enum.any?(get_in(payload, ["issue", "states"]), fn state ->
             state["routeKey"] == "review" and state["name"] == "status_5"
           end)
  end

  test "tapd_move_issue resolves route keys and updates raw TAPD status" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())

    test_pid = self()
    record_review_ready_evidence(["1153000000000000001", "TAPD-1153000000000000001"])

    response =
      Bridge.execute(
        "tapd_move_issue",
        %{
          "issue_id" => "1153000000000000001",
          "state_name" => "review",
          "expected_current_state" => "in_progress"
        },
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true, inspect(response)
    assert get_in(response["payload"], ["issue", "state", "name"]) == "status_5"

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/stories",
                       params: %{
                         "id" => "1153000000000000001",
                         "status" => "status_5",
                         "workspace_id" => "53000000"
                       }
                     }}
  end

  test "tapd_move_issue blocks review handoff until structured evidence is complete" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())

    test_pid = self()
    base_request_fun = tapd_typed_tool_request_fun(test_pid)

    response =
      Bridge.execute(
        "tapd_move_issue",
        %{
          "issue_id" => "1153000000000000001",
          "state_name" => "review",
          "expected_current_state" => "in_progress"
        },
        request_fun: fn
          %{method: "POST", url: "https://api.tapd.cn/stories"} ->
            flunk("review handoff gate must fail before calling TAPD Story update")

          request ->
            base_request_fun.(request)
        end
      )

    assert_received {:tapd_typed_request, %{method: "GET", url: "https://api.tapd.cn/stories"}}

    assert response["success"] == false
    assert get_in(response, ["payload", "error", "code"]) == "transition_readiness_not_ready"

    missing = get_in(response, ["payload", "error", "details", "missing_evidence"])

    assert Enum.any?(missing, &(Map.get(&1, "code") == "workpad_record_missing"))
  end

  test "tapd_upsert_workpad writes the provided body without parsing sections" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())
    register_tapd_workpad!("1153000000000000001", "1153000000000000999")

    test_pid = self()

    response =
      Bridge.execute(
        "tapd_upsert_workpad",
        %{
          "issue_id" => "1153000000000000001",
          "body" => "### Plan\n\n- [x] done"
        },
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true

    assert get_in(response["payload"], ["comment", "id"]) ==
             "tapd:issue:1153000000000000001:workpad"

    assert get_in(response["payload"], ["comment", "provider_ref"]) ==
             %{"type" => "comment", "id" => "1153000000000000999"}

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/comments",
                       params: %{
                         "id" => "1153000000000000999",
                         "description" => encoded_description,
                         "workspace_id" => "53000000"
                       }
                     }}

    assert encoded_description ==
             CommentCodec.encode_description("### Plan\n\n- [x] done")
  end

  test "tapd_upsert_workpad replaces stale comment ids by creating a new registered workpad" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())
    register_tapd_workpad!("1153000000000000001", "stale-comment-id")

    test_pid = self()

    response =
      Bridge.execute(
        "tapd_upsert_workpad",
        %{
          "issue_id" => "1153000000000000001",
          "workpad_id" => "tapd:issue:1153000000000000001:workpad",
          "body" => "### Plan\n\n- [x] recovered"
        },
        request_fun: tapd_stale_comment_recovery_request_fun(test_pid)
      )

    assert response["success"] == true
    assert get_in(response["payload"], ["comment", "id"]) == "tapd:issue:1153000000000000001:workpad"
    assert get_in(response["payload"], ["comment", "provider_ref"]) == %{"type" => "comment", "id" => "1153000000000000999"}

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/comments",
                       params: %{"id" => "stale-comment-id"}
                     }}

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/comments",
                       params: %{
                         "description" => encoded_description,
                         "entry_id" => "1153000000000000001",
                         "entry_type" => "stories",
                         "workspace_id" => "53000000"
                       }
                     }}

    assert encoded_description ==
             CommentCodec.encode_description("### Plan\n\n- [x] recovered")
  end

  test "tapd_attach_external_reference stores external links in the canonical workpad comment" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())
    register_tapd_workpad!("1153000000000000001", "1153000000000000999")

    test_pid = self()

    response =
      Bridge.execute(
        "tapd_attach_external_reference",
        %{
          "issue_id" => "1153000000000000001",
          "url" => "https://github.com/acme/widgets/pull/42",
          "title" => "Typed TAPD external reference",
          "reference_kind" => "change_proposal",
          "provider_kind" => "github",
          "external_id" => "42",
          "metadata" => %{"repository" => "acme/widgets"}
        },
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true

    payload = response["payload"]
    assert get_in(payload, ["attachment", "storage"]) == "workpad_comment"
    assert get_in(payload, ["attachment", "url"]) == "https://github.com/acme/widgets/pull/42"

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/comments",
                       params: %{
                         "id" => "1153000000000000999",
                         "description" => encoded_description,
                         "workspace_id" => "53000000"
                       }
                     }}

    assert encoded_description =~ "Typed TAPD external reference"
    assert encoded_description =~ "https://github.com/acme/widgets/pull/42"
    assert encoded_description =~ "External Reference"
  end

  test "tapd_upsert_comment creates and updates non-workpad comments" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())

    test_pid = self()

    assert %{"success" => true} =
             Bridge.execute(
               "tapd_upsert_comment",
               %{"issue_id" => "TAPD-1153000000000000001", "body" => "General validation note"},
               request_fun: tapd_typed_tool_request_fun(test_pid)
             )

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/comments",
                       params: %{
                         "entry_id" => "1153000000000000001",
                         "entry_type" => "stories",
                         "description" => created_description,
                         "workspace_id" => "53000000"
                       }
                     }}

    assert created_description == CommentCodec.encode_description("General validation note")

    assert %{"success" => true} =
             Bridge.execute(
               "tapd_upsert_comment",
               %{"comment_id" => "1153000000000000999", "body" => "Updated validation note"},
               request_fun: tapd_typed_tool_request_fun(test_pid)
             )

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/comments",
                       params: %{
                         "id" => "1153000000000000999",
                         "description" => updated_description,
                         "workspace_id" => "53000000"
                       }
                     }}

    assert updated_description == CommentCodec.encode_description("Updated validation note")
  end

  test "tapd_create_follow_up_story owns restricted Story creation params" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())

    test_pid = self()

    response =
      Bridge.execute(
        "tapd_create_follow_up_story",
        %{
          "source_issue_id" => "TAPD-1153000000000000001",
          "title" => "Follow-up: clean up TAPD link sync",
          "description" => "Acceptance Criteria\n- keep current scope unchanged",
          "workitem_type_id" => "1153000000000000009",
          "priority_label" => "P2",
          "label" => "follow-up|symphony"
        },
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true
    assert get_in(response["payload"], ["story", "id"]) == "1153000000000000010"

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/stories",
                       params: %{
                         "description" => "Acceptance Criteria\n- keep current scope unchanged",
                         "label" => "follow-up|symphony",
                         "name" => "Follow-up: clean up TAPD link sync",
                         "parent_id" => "1153000000000000001",
                         "priority_label" => "P2",
                         "workitem_type_id" => "1153000000000000009",
                         "workspace_id" => "53000000"
                       }
                     }}
  end

  test "tapd relation typed tools read and create direct Story links" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())

    test_pid = self()

    response =
      Bridge.execute(
        "tapd_read_story_relations",
        %{"issue_id" => "TAPD-1153000000000000001"},
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true
    assert [relation] = get_in(response["payload"], ["relations"])
    assert relation["src_story_id"] == "1153000000000000001"

    assert_received {:tapd_typed_request,
                     %{
                       method: "GET",
                       url: "https://api.tapd.cn/stories/get_link_stories",
                       params: %{
                         "story_id" => "1153000000000000001",
                         "workspace_id" => "53000000"
                       }
                     }}

    response =
      Bridge.execute(
        "tapd_add_story_relation",
        %{
          "source_issue_id" => "TAPD-1153000000000000001",
          "target_issue_id" => "TAPD-1153000000000000010"
        },
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true

    assert get_in(response["payload"], ["relation", "targetIssueId"]) ==
             "1153000000000000010"

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/stories/add_story_link_relations",
                       params: %{
                         "src_story_id" => "1153000000000000001",
                         "target_story_id" => "1153000000000000010",
                         "workspace_id" => "53000000"
                       }
                     }}
  end

  test "tapd dependency typed tools read blockers and save one semantic dependency" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_typed_tool_workflow_config())

    test_pid = self()

    response =
      Bridge.execute(
        "tapd_read_story_dependencies",
        %{"issue_id" => "TAPD-1153000000000000001"},
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true

    assert [%{"id" => "1153000000000000002"}] =
             get_in(response["payload"], ["blockedBy"])

    assert_received {:tapd_typed_request,
                     %{
                       method: "GET",
                       url: "https://api.tapd.cn/stories/get_time_relative_stories",
                       params: %{
                         "story_id" => "1153000000000000001",
                         "workspace_id" => "53000000"
                       }
                     }}

    response =
      Bridge.execute(
        "tapd_save_story_dependency",
        %{
          "blocking_issue_id" => "TAPD-1153000000000000002",
          "blocked_issue_id" => "TAPD-1153000000000000001",
          "current_user" => "symphony"
        },
        request_fun: tapd_typed_tool_request_fun(test_pid)
      )

    assert response["success"] == true
    assert get_in(response["payload"], ["dependency", "srcField"]) == "due"

    assert_received {:tapd_typed_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/stories/save_time_relations",
                       params: %{
                         "relations[0][workitem_id]" => "1153000000000000002",
                         "relations[0][dst_workitem_id]" => "1153000000000000001",
                         "relations[0][src_field]" => "due",
                         "relations[0][dst_field]" => "begin",
                         "current_user" => "symphony",
                         "workspace_id" => "53000000"
                       }
                     }}
  end

  defp tapd_route_policy_workflow_config(overrides) do
    Keyword.merge(
      [
        tracker_kind: "tapd",
        tracker_endpoint: nil,
        tracker_api_token: "tapd-user",
        tracker_api_secret: "tapd-secret",
        tracker_project_slug: nil,
        tracker_assignee: nil,
        tracker_active_states: ["status_4", "developing", "merging", "rework"],
        tracker_terminal_states: ["resolved", "rejected"],
        tracker_state_phase_map: %{
          "status_4" => "todo",
          "developing" => "in_progress",
          "status_5" => "human_review",
          "merging" => "merging",
          "rework" => "rework",
          "resolved" => "done",
          "rejected" => "canceled"
        },
        tracker_raw_state_by_route_key: %{
          "planning" => "status_4",
          "developing" => "developing",
          "review" => "status_5",
          "merging" => "merging",
          "rework" => "rework",
          "resolved" => "resolved",
          "rejected" => "rejected"
        },
        tracker_platform: %{"workspace_id" => "53000000"}
      ],
      overrides
    )
  end

  defp record_review_ready_evidence(issue_keys) do
    ReadinessStore.record(issue_keys, %{
      "observations" => %{
        "workpad" => %{
          "status" => "updated",
          "source" => "typed_tool_observed",
          "workpad_id" => "tapd:issue:1153000000000000001:workpad",
          "updated_at" => "2026-05-19T08:06:00Z"
        },
        "repo" => %{
          "change_kind" => "code_change",
          "source" => "repo_observed",
          "head_sha" => "head-tapd",
          "commits" => [%{"sha" => "head-tapd"}]
        },
        "change_proposal" => %{
          "status" => "updated",
          "source" => "repo_provider_observed",
          "url" => "https://github.com/acme/widgets/pull/42",
          "head_sha" => "head-tapd",
          "linked_to_tracker" => true
        },
        "validation" => %{
          "status" => "passed",
          "source" => "typed_tool_observed",
          "head_sha" => "head-tapd",
          "commands" => [%{"command" => "mix test", "exit_code" => 0, "head_sha" => "head-tapd"}]
        },
        "checks" => %{
          "status" => "passed",
          "source" => "repo_provider_observed",
          "head_sha" => "head-tapd"
        },
        "feedback" => %{
          "status" => "clear",
          "source" => "repo_provider_observed",
          "actionable_count" => 0
        }
      }
    })
  end

  defp tapd_typed_tool_workflow_config(overrides \\ []) do
    tapd_route_policy_workflow_config(overrides)
  end

  defp tapd_typed_tool_request_fun(test_pid) do
    fn request ->
      send(test_pid, {:tapd_typed_request, request})

      case {request.method, request.url} do
        {"GET", "https://api.tapd.cn/stories"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "status" => 1,
               "data" => [
                 %{
                   "Story" => %{
                     "id" => "1153000000000000001",
                     "name" => "Typed TAPD Story",
                     "description" => "Story body",
                     "status" => "developing",
                     "workitem_type_id" => "1153070854001000001",
                     "label" => "typed,workflow"
                   }
                 }
               ]
             }
           }}

        {"GET", "https://api.tapd.cn/stories/get_time_relative_stories"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "status" => 1,
               "data" => [
                 %{
                   "WorkitemTimeRelation" => %{
                     "workitem_id" => "1153000000000000002",
                     "dst_workitem_id" => "1153000000000000001",
                     "src_field" => "due",
                     "dst_field" => "begin"
                   }
                 }
               ]
             }
           }}

        {"GET", "https://api.tapd.cn/stories/get_link_stories"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "status" => 1,
               "data" => [
                 %{
                   "StoryLinkRelation" => %{
                     "src_story_id" => "1153000000000000001",
                     "target_story_id" => "1153000000000000010"
                   }
                 }
               ]
             }
           }}

        {"GET", "https://api.tapd.cn/comments"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "status" => 1,
               "data" => [
                 %{
                   "Comment" => %{
                     "id" => "1153000000000000999",
                     "description" => "### Plan\n\n- [ ] existing\n\n### Acceptance Criteria\n\n- [ ] done\n\n### Validation\n\n- [ ] tests\n\n### Notes\n\n- note",
                     "author" => "symphony"
                   }
                 }
               ]
             }
           }}

        {"POST", "https://api.tapd.cn/stories"} ->
          case request.params do
            %{"name" => name} ->
              {:ok,
               %{
                 status: 200,
                 body: %{
                   "status" => 1,
                   "data" => %{
                     "Story" => %{
                       "id" => "1153000000000000010",
                       "name" => name,
                       "description" => Map.get(request.params, "description"),
                       "parent_id" => Map.get(request.params, "parent_id"),
                       "workitem_type_id" => Map.get(request.params, "workitem_type_id")
                     }
                   }
                 }
               }}

            _params ->
              {:ok, %{status: 200, body: %{"status" => 1, "data" => %{}}}}
          end

        {"POST", "https://api.tapd.cn/stories/add_story_link_relations"} ->
          {:ok, %{status: 200, body: %{"status" => 1, "data" => %{"success" => 1}}}}

        {"POST", "https://api.tapd.cn/stories/save_time_relations"} ->
          {:ok, %{status: 200, body: %{"status" => 1, "data" => %{"result" => true}}}}

        {"POST", "https://api.tapd.cn/comments"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "status" => 1,
               "data" => %{
                 "id" => Map.get(request.params, "id", "1153000000000000999"),
                 "description" => Map.get(request.params, "description")
               }
             }
           }}
      end
    end
  end

  defp tapd_stale_comment_recovery_request_fun(test_pid) do
    base_fun = tapd_typed_tool_request_fun(test_pid)

    fn
      %{
        method: "POST",
        url: "https://api.tapd.cn/comments",
        params: %{"id" => "stale-comment-id"}
      } = request ->
        send(test_pid, {:tapd_typed_request, request})

        {:ok,
         %{
           status: 422,
           body: %{
             "status" => 422,
             "data" => "",
             "info" => "comment stale-comment-id not exist in workspace 53000000"
           }
         }}

      request ->
        base_fun.(request)
    end
  end

  defp register_tapd_workpad!(issue_id, comment_id) do
    assert {:ok, _record} =
             SymphonyElixir.Tracker.WorkpadRegistry.register(%{
               "tracker_kind" => "tapd",
               "issue_id" => issue_id,
               "id" => "tapd:issue:" <> issue_id <> ":workpad",
               "provider_ref" => %{"type" => "comment", "id" => comment_id},
               "provider" => "tapd"
             })
  end

  defp tapd_requirement_analysis_workflow_config(overrides) do
    Keyword.merge(
      [
        tracker_kind: "tapd",
        tracker_endpoint: nil,
        tracker_api_token: "tapd-user",
        tracker_api_secret: "tapd-secret",
        tracker_project_slug: nil,
        tracker_assignee: nil,
        workflow_profile_kind: "requirement_analysis",
        tracker_active_states: ["intake", "analyzing"],
        tracker_terminal_states: ["ready", "rejected"],
        tracker_state_phase_map: %{
          "intake" => "todo",
          "analyzing" => "in_progress",
          "needs_info" => "human_review",
          "review" => "human_review",
          "ready" => "done",
          "rejected" => "canceled"
        },
        tracker_raw_state_by_route_key: %{
          "intake" => "intake",
          "analyzing" => "analyzing",
          "needs_info" => "needs_info",
          "review" => "review",
          "ready" => "ready",
          "rejected" => "rejected"
        },
        tracker_platform: %{"workspace_id" => "53000000"}
      ],
      overrides
    )
  end

  defp coding_route_ref(route_key), do: route_ref("coding_pr_delivery", 1, route_key)

  defp requirement_analysis_route_ref(route_key), do: route_ref("requirement_analysis", 1, route_key)

  defp route_ref(profile_kind, profile_version, route_key) do
    %RouteRef{profile_kind: profile_kind, profile_version: profile_version, route_key: route_key}
  end

  defp invalid_coding_route_key(route_key), do: invalid_route_key("coding_pr_delivery", 1, route_key)

  defp invalid_requirement_analysis_route_key(route_key), do: invalid_route_key("requirement_analysis", 1, route_key)

  defp invalid_route_key(profile_kind, profile_version, route_key) do
    {:invalid_workflow_route_key, profile_kind, profile_version, route_key}
  end

  defp assert_validate_error(source_reason, code \\ :invalid_configuration) do
    assert {:error,
            %TrackerError{
              provider: "tapd",
              operation: :validate_config,
              code: ^code,
              details: %{source_reason: ^source_reason}
            }} = Config.validate!()
  end
end
