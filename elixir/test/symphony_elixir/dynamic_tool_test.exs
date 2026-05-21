defmodule SymphonyElixir.Agent.DynamicToolTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Bridge
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store, as: ReadinessStore

  defmodule InvalidResultAdapter do
    @behaviour SymphonyElixir.Tracker.Adapter

    def kind, do: "invalid_dynamic_result"
    def defaults, do: %{}
    def validate_config(_tracker), do: :ok

    def execute_dynamic_tool(_tracker, _tool, _arguments, _opts) do
      :invalid_tool_result
    end
  end

  test "tool_specs advertises typed Linear tools and omits retired raw GraphQL" do
    specs = DynamicTool.tool_specs()
    names = Enum.map(specs, &Map.fetch!(&1, "name"))

    assert Enum.sort(names) == Enum.sort(default_tool_names())
    refute "linear_graphql" in names
    assert "linear_upsert_comment" in names
    assert "linear_prepare_file_upload" in names
    assert "linear_provider_diagnostics" in names
  end

  test "linear_graphql execution is rejected after physical retirement" do
    response =
      Bridge.execute(
        "linear_graphql",
        %{"query" => "query Viewer { viewer { id } }"},
        linear_client: fn _query, _variables, _opts ->
          flunk("linear client should not be called when raw GraphQL is not advertised")
        end
      )

    assert response["success"] == false

    assert %{
             "error" => %{
               "code" => "unsupported_tool",
               "message" => ~s(Unsupported dynamic tool: "linear_graphql".),
               "supportedTools" => supported_tools
             }
           } = response["payload"]

    refute "linear_graphql" in supported_tools
    assert "linear_issue_snapshot" in supported_tools
    assert "linear_upsert_comment" in supported_tools
  end

  test "captured Linear tool context preserves typed workflow metadata" do
    context = DynamicTool.capture_context()

    assert context.tool_metadata["linear_issue_snapshot"]["workflowCapability"] ==
             "tracker.issue_snapshot"

    assert context.tool_metadata["linear_issue_snapshot"]["sourceKind"] == "linear"
    assert context.tool_metadata["linear_issue_snapshot"]["sideEffect"] == "read_only"

    assert context.tool_metadata["linear_move_issue"]["workflowCapability"] ==
             "tracker.move_issue"

    assert context.tool_metadata["linear_move_issue"]["sideEffect"] == "write"

    assert context.tool_metadata["linear_upsert_comment"]["workflowCapability"] ==
             "tracker.upsert_comment"

    assert context.tool_metadata["linear_prepare_file_upload"]["workflowCapability"] ==
             "tracker.prepare_file_upload"

    assert context.tool_metadata["linear_provider_diagnostics"]["sideEffect"] == "read_only"

    assert context.tool_metadata["repo_create_or_update_change_proposal"]["workflowCapability"] ==
             "repo.create_or_update_change_proposal"

    assert context.tool_metadata["repo_create_or_update_change_proposal"]["sourceKind"] ==
             "github"

    assert context.tool_metadata["repo_read_change_proposal_checks"]["sideEffect"] == "read_only"

    assert context.tool_metadata["repo_add_change_proposal_comment"]["workflowCapability"] ==
             "repo.add_change_proposal_comment"

    assert context.tool_metadata["repo_submit_change_proposal_review"]["workflowCapability"] ==
             "repo.submit_change_proposal_review"

    assert context.tool_metadata["repo_reply_change_proposal_review_comment"][
             "workflowCapability"
           ] == "repo.reply_change_proposal_review_comment"
  end

  test "captured TAPD tool context preserves the session snapshot across workflow changes" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    captured_context =
      DynamicTool.capture_context(dynamic_tool_source: SymphonyElixir.Tracker.DynamicToolSource)

    assert captured_context.source_kind == "tapd"
    assert captured_context.source_context.kind == "tapd"

    names =
      DynamicTool.tool_specs(tool_context: captured_context)
      |> Enum.map(&Map.fetch!(&1, "name"))

    refute "tapd_api" in names
    assert "tapd_issue_snapshot" in names
    assert "tapd_move_issue" in names
    assert "tapd_upsert_workpad" in names
    assert "tapd_attach_change_proposal" in names
    assert "tapd_upsert_comment" in names
    assert "tapd_create_follow_up_story" in names
    assert "tapd_read_story_relations" in names
    assert "tapd_add_story_relation" in names
    assert "tapd_read_story_dependencies" in names
    assert "tapd_save_story_dependency" in names
    assert "tapd_provider_diagnostics" in names

    assert captured_context.tool_metadata["tapd_issue_snapshot"]["workflowCapability"] ==
             "tracker.issue_snapshot"

    assert captured_context.tool_metadata["tapd_issue_snapshot"]["sourceKind"] == "tapd"

    assert captured_context.tool_metadata["tapd_move_issue"]["workflowCapability"] ==
             "tracker.move_issue"

    assert captured_context.tool_metadata["tapd_upsert_workpad"]["workflowCapability"] ==
             "tracker.upsert_workpad"

    assert captured_context.tool_metadata["tapd_attach_change_proposal"]["workflowCapability"] ==
             "tracker.attach_change_proposal"

    assert captured_context.tool_metadata["tapd_upsert_comment"]["workflowCapability"] ==
             "tracker.upsert_comment"

    assert captured_context.tool_metadata["tapd_create_follow_up_story"]["workflowCapability"] ==
             "tracker.create_follow_up_issue"

    assert captured_context.tool_metadata["tapd_read_story_relations"]["workflowCapability"] ==
             "tracker.read_issue_relations"

    assert captured_context.tool_metadata["tapd_add_story_relation"]["workflowCapability"] ==
             "tracker.add_issue_relation"

    assert captured_context.tool_metadata["tapd_read_story_dependencies"]["workflowCapability"] ==
             "tracker.read_issue_dependencies"

    assert captured_context.tool_metadata["tapd_save_story_dependency"]["workflowCapability"] ==
             "tracker.save_issue_dependency"

    assert captured_context.tool_metadata["tapd_provider_diagnostics"]["workflowCapability"] ==
             "tracker.provider_diagnostics"

    assert captured_context.tool_metadata["tapd_provider_diagnostics"]["sideEffect"] ==
             "read_only"

    write_workflow_file!(Workflow.workflow_file_path())

    assert DynamicTool.tool_specs() |> Enum.map(&Map.fetch!(&1, "name")) |> Enum.sort() ==
             Enum.sort(default_tool_names())
  end

  test "unsupported tools return a failure payload with the supported tool list" do
    response = Bridge.execute("not_a_real_tool", %{})

    assert response["success"] == false

    assert response["payload"] == %{
             "error" => %{
               "code" => "unsupported_tool",
               "message" => ~s(Unsupported dynamic tool: "not_a_real_tool".),
               "supportedTools" => default_tool_names()
             }
           }

    refute Map.has_key?(response, "contentItems")
    refute Map.has_key?(response, "output")
  end

  test "dynamic tools normalize invalid tracker result shapes into failure payloads" do
    previous_adapters = Application.get_env(:symphony_elixir, :tracker_adapters)

    Application.put_env(:symphony_elixir, :tracker_adapters, %{
      "invalid_dynamic_result" => InvalidResultAdapter
    })

    on_exit(fn ->
      case previous_adapters do
        nil -> Application.delete_env(:symphony_elixir, :tracker_adapters)
        adapters -> Application.put_env(:symphony_elixir, :tracker_adapters, adapters)
      end
    end)

    tool_context = %{
      source: SymphonyElixir.Tracker.DynamicToolSource,
      source_context: %{kind: "invalid_dynamic_result"},
      tool_specs: [
        %{
          "name" => "invalid_result_tool",
          "description" => "Returns an invalid tracker result shape.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      tool_metadata: %{
        "invalid_result_tool" => %{
          "schemaVersion" => "1",
          "sideEffect" => "read_only",
          "riskFlags" => []
        }
      },
      tool_environment: %{}
    }

    response = Bridge.execute("invalid_result_tool", %{}, tool_context: tool_context)

    assert response["success"] == false

    assert response["payload"] == %{
             "error" => %{
               "message" => "Dynamic tool execution returned an invalid result.",
               "result" => ":invalid_tool_result"
             }
           }
  end

  test "dynamic tools emit audit log events without leaking secrets" do
    issue = %Issue{id: "issue-audit", identifier: "MT-500"}

    log =
      capture_log(fn ->
        response =
          Bridge.execute(
            "linear_upsert_comment",
            %{
              "comment_id" => "comment-500",
              "body" => "token=top-secret-token"
            },
            issue: issue,
            session_id: "thread-500-turn-500",
            thread_id: "thread-500",
            turn_id: "turn-500",
            workspace: "/tmp/symphony/MT-500",
            worker_host: "local",
            linear_client: fn query, variables, _opts ->
              assert query =~ "commentUpdate"
              assert variables == %{commentId: "comment-500", body: "token=top-secret-token"}
              {:ok, linear_comment_update_response()}
            end
          )

        assert response["success"] == true
      end)

    assert log =~ "tool_call_requested"
    assert log =~ "tool_call_succeeded"
    refute log =~ "top-secret-token"
  end

  test "dynamic tool audit events classify typed raw and fallback usage" do
    previous_adapters = Application.get_env(:symphony_elixir, :tracker_adapters)

    Application.put_env(:symphony_elixir, :tracker_adapters, %{
      "invalid_dynamic_result" => InvalidResultAdapter
    })

    EventStore.reset()

    on_exit(fn ->
      case previous_adapters do
        nil -> Application.delete_env(:symphony_elixir, :tracker_adapters)
        adapters -> Application.put_env(:symphony_elixir, :tracker_adapters, adapters)
      end

      EventStore.reset()
    end)

    context = invalid_result_tool_context()

    capture_log(fn ->
      Bridge.execute("typed_probe", %{}, tool_context: context)

      Bridge.execute("raw_probe", %{},
        tool_context: context,
        typed_workflow_tool_fallback_policy: %{
          "tracker.issue_snapshot" => %{
            "tool" => "raw_probe",
            "reason" => "temporary provider migration"
          }
        }
      )
    end)

    events = EventStore.recent_events(limit: 20)

    typed_event =
      Enum.find(events, &(&1["event"] == "tool_call_failed" and &1["tool_name"] == "typed_probe"))

    fallback_event =
      Enum.find(events, &(&1["event"] == "tool_call_failed" and &1["tool_name"] == "raw_probe"))

    assert typed_event["dynamic_tool_usage_kind"] == "typed"
    assert typed_event["dynamic_tool_workflow_capability"] == "tracker.issue_snapshot"
    assert typed_event["dynamic_tool_side_effect"] == "read_only"

    assert typed_event["dynamic_tool_failure_reason"] ==
             "Dynamic tool execution returned an invalid result."

    assert fallback_event["dynamic_tool_usage_kind"] == "fallback"
    assert fallback_event["dynamic_tool_workflow_capability"] == "tracker.issue_snapshot"
    assert fallback_event["dynamic_tool_fallback_reason"] == "temporary provider migration"

    metrics = EventStore.dynamic_tool_usage_metrics()

    assert metrics["total_calls"] == 2
    assert metrics["typed_calls"] == 1
    assert metrics["fallback_calls"] == 1
    assert metrics["raw_calls"] == 0

    assert metrics["failure_reasons"] == %{
             "Dynamic tool execution returned an invalid result." => 2
           }
  end

  test "typed linear provider diagnostics uses a fixed read-only query" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_provider_diagnostics",
        %{},
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})
          {:ok, %{"data" => %{"viewer" => %{"id" => "usr_123", "name" => "Agent"}}}}
        end
      )

    assert_received {:linear_client_called, query, %{}, []}
    assert query =~ "SymphonyLinearProviderDiagnostics"
    assert query =~ "viewer"

    assert response["success"] == true
    assert get_in(response["payload"], ["data", "viewer", "id"]) == "usr_123"
  end

  test "typed TAPD provider diagnostics uses a fixed read-only request" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: nil,
      tracker_api_token: "tapd-user",
      tracker_api_secret: "tapd-secret",
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: ["planning"],
      tracker_terminal_states: ["resolved"],
      tracker_platform: %{"workspace_id" => "53000000"}
    )

    test_pid = self()

    response =
      Bridge.execute(
        "tapd_provider_diagnostics",
        %{},
        request_fun: fn request ->
          send(test_pid, {:tapd_diagnostics_request, request})
          {:ok, %{status: 200, body: %{"status" => 1, "data" => %{"ok" => true}}}}
        end
      )

    assert_received {:tapd_diagnostics_request,
                     %{
                       method: "GET",
                       params: %{"workspace_id" => "53000000"},
                       url: "https://api.tapd.cn/quickstart/testauth"
                     }}

    assert response["success"] == true
    payload = response["payload"]
    assert get_in(payload, ["workspace", "id"]) == "53000000"
    assert get_in(payload, ["auth", "data", "ok"]) == true
  end

  test "typed linear comment upsert updates a specific non-workpad comment" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_upsert_comment",
        %{
          "comment_id" => "comment-discussion",
          "body" => "Updated discussion note",
          "asset_urls" => ["https://uploads.linear.app/asset/video.mp4"]
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})
          assert query =~ "commentUpdate"

          assert variables == %{
                   commentId: "comment-discussion",
                   body: "Updated discussion note\n\nAttached assets:\n- https://uploads.linear.app/asset/video.mp4"
                 }

          {:ok, linear_comment_update_response()}
        end
      )

    assert_received {:linear_client_called, update_query, _variables, []}
    assert update_query =~ "commentUpdate"
    assert response["success"] == true
    assert get_in(response["payload"], ["data", "comment", "updated"]) == true
  end

  test "typed linear comment upsert creates a comment when comment_id is omitted" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_upsert_comment",
        %{"issue_id" => "DEMO-16", "body" => "New discussion note"},
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})
          assert query =~ "commentCreate"
          assert variables == %{issueId: "DEMO-16", body: "New discussion note"}
          {:ok, linear_comment_create_response("New discussion note")}
        end
      )

    assert_received {:linear_client_called, create_query, _variables, []}
    assert create_query =~ "commentCreate"
    assert response["success"] == true
    assert get_in(response["payload"], ["data", "comment", "created"]) == true
  end

  test "typed linear file upload preparation uses the fixed fileUpload mutation" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_prepare_file_upload",
        %{
          "filename" => "demo.mp4",
          "content_type" => "video/mp4",
          "size" => 42,
          "make_public" => true
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})
          assert query =~ "fileUpload"

          assert variables == %{
                   filename: "demo.mp4",
                   contentType: "video/mp4",
                   size: 42,
                   makePublic: true
                 }

          {:ok, linear_file_upload_response()}
        end
      )

    assert_received {:linear_client_called, upload_query, _variables, []}
    assert upload_query =~ "uploadFile"
    assert response["success"] == true

    assert get_in(response["payload"], ["data", "upload_file", "assetUrl"]) ==
             "https://uploads.linear.app/asset/demo.mp4"
  end

  test "typed linear file upload preparation preserves explicit false booleans" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_prepare_file_upload",
        %{
          "filename" => "demo.txt",
          "content_type" => "text/plain",
          "size" => 12,
          "make_public" => false
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          assert variables == %{
                   filename: "demo.txt",
                   contentType: "text/plain",
                   size: 12,
                   makePublic: false
                 }

          {:ok, linear_file_upload_response()}
        end
      )

    assert_received {:linear_client_called, upload_query, _variables, []}
    assert upload_query =~ "fileUpload"
    assert response["success"] == true
  end

  test "typed linear file upload preparation validates required shape before calling Linear" do
    response =
      Bridge.execute(
        "linear_prepare_file_upload",
        %{"filename" => "demo.mp4", "content_type" => "video/mp4", "size" => 0},
        linear_client: fn _query, _variables, _opts ->
          flunk("linear client should not be called when upload size is invalid")
        end
      )

    assert response["success"] == false

    assert response["payload"] == %{
             "error" => %{
               "code" => "invalid_arguments",
               "details" => %{},
               "message" => "size must be a positive integer."
             }
           }
  end

  test "typed linear issue snapshot uses a fixed query and returns the typed envelope" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_issue_snapshot",
        %{"issue_id" => "DEMO-16", "workpad_heading" => "## Claude Code Workpad"},
        dynamic_tool_policy: %{allowed_side_effects: ["read_only"]},
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})
          {:ok, linear_issue_snapshot_response()}
        end
      )

    assert_received {:linear_client_called, query, %{issueId: "DEMO-16", commentFirst: 50}, []}
    assert query =~ "branchName"
    assert query =~ "resolvedAt"
    refute query =~ "Comment.resolved"

    assert response["success"] == true

    assert %{
             "data" => %{
               "issue" => %{
                 "identifier" => "DEMO-16",
                 "branchName" => "symphony/demo-16",
                 "comments" => [%{"id" => "comment-1"}]
               },
               "workpad" => %{"id" => "comment-1"}
             },
             "warnings" => []
           } = response["payload"]
  end

  test "typed linear issue snapshot preserves explicit false include flags" do
    response =
      Bridge.execute(
        "linear_issue_snapshot",
        %{"issue_id" => "DEMO-16", "include_comments" => false, "include_attachments" => false},
        linear_client: fn _query, _variables, _opts ->
          {:ok, linear_issue_snapshot_response()}
        end
      )

    assert response["success"] == true

    assert %{
             "data" => %{
               "issue" => %{
                 "comments" => [],
                 "attachments" => []
               },
               "workpad" => %{"id" => "comment-1"}
             }
           } = response["payload"]
  end

  test "typed linear issue move resolves state ids before calling issueUpdate" do
    test_pid = self()
    record_review_ready_evidence("DEMO-16")

    response =
      Bridge.execute(
        "linear_move_issue",
        %{
          "issue_id" => "DEMO-16",
          "state_name" => "In Review",
          "expected_current_state" => "In Progress"
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          cond do
            query =~ "issueUpdate" ->
              assert variables == %{issueId: "DEMO-16", stateId: "state-review"}
              {:ok, linear_issue_update_response("In Review")}

            true ->
              {:ok, linear_issue_review_ready_response()}
          end
        end
      )

    assert_received {:linear_client_called, states_query, %{issueId: "DEMO-16", commentFirst: 50}, []}
    assert states_query =~ "team"
    assert states_query =~ "comments"
    assert states_query =~ "attachments"

    assert_received {:linear_client_called, update_query, %{issueId: "DEMO-16", stateId: "state-review"}, []}

    assert update_query =~ "issueUpdate"

    assert response["success"] == true

    assert get_in(response["payload"], ["data", "issue", "state", "name"]) ==
             "In Review"
  end

  test "typed linear issue move blocks review handoff until structured evidence is complete" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_move_issue",
        %{
          "issue_id" => "DEMO-16",
          "state_name" => "In Review",
          "expected_current_state" => "In Progress"
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          if query =~ "issueUpdate" do
            flunk("review handoff gate must fail before calling issueUpdate")
          else
            {:ok, linear_issue_review_incomplete_response()}
          end
        end
      )

    assert_received {:linear_client_called, snapshot_query, %{issueId: "DEMO-16", commentFirst: 50}, []}
    assert snapshot_query =~ "comments"
    assert snapshot_query =~ "attachments"

    assert response["success"] == false
    assert get_in(response["payload"], ["error", "code"]) == "review_handoff_not_ready"

    missing = get_in(response["payload"], ["error", "details", "missing_evidence"])

    assert Enum.any?(missing, &(Map.get(&1, "code") == "workpad_record_missing"))
  end

  test "typed linear issue move does not run review handoff checks for non-review states" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_move_issue",
        %{
          "issue_id" => "DEMO-16",
          "state_name" => "Rework",
          "expected_current_state" => "In Progress"
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          cond do
            query =~ "issueUpdate" ->
              assert variables == %{issueId: "DEMO-16", stateId: "state-rework"}
              {:ok, linear_issue_update_response("Rework")}

            true ->
              {:ok, linear_issue_states_response()}
          end
        end
      )

    assert_received {:linear_client_called, states_query, %{issueId: "DEMO-16"}, []}
    assert states_query =~ "team"
    refute states_query =~ "comments"
    refute states_query =~ "attachments"

    assert_received {:linear_client_called, update_query, %{issueId: "DEMO-16", stateId: "state-rework"}, []}
    assert update_query =~ "issueUpdate"

    assert response["success"] == true
    assert get_in(response["payload"], ["data", "issue", "state", "name"]) == "Rework"
  end

  test "typed linear workpad upsert updates the existing active workpad comment" do
    test_pid = self()

    response =
      Bridge.execute(
        "linear_upsert_workpad",
        %{
          "issue_id" => "DEMO-16",
          "heading" => "## Claude Code Workpad",
          "body" => "## Claude Code Workpad\n\nupdated"
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          cond do
            query =~ "commentUpdate" ->
              assert variables == %{
                       commentId: "comment-1",
                       body: "## Claude Code Workpad\n\nupdated"
                     }

              {:ok, linear_comment_update_response()}

            query =~ "commentCreate" ->
              flunk("typed workpad upsert should not create a duplicate active workpad")

            true ->
              {:ok, linear_issue_snapshot_response()}
          end
        end
      )

    assert_received {:linear_client_called, comments_query, %{issueId: "DEMO-16", first: 50}, []}
    assert comments_query =~ "comments"

    assert_received {:linear_client_called, update_query, %{commentId: "comment-1", body: "## Claude Code Workpad\n\nupdated"}, []}

    assert update_query =~ "commentUpdate"

    assert response["success"] == true
    assert get_in(response["payload"], ["data", "comment", "updated"]) == true
  end

  test "typed linear workpad upsert prefixes the canonical heading before creating a comment" do
    test_pid = self()

    body = """
    ```text
    host:/workspace/repo@abc123
    ```

    ### Plan

    - [ ] Validate workflow
    """

    expected_body = "## Claude Code Workpad\n\n" <> String.trim(body)

    response =
      Bridge.execute(
        "linear_upsert_workpad",
        %{
          "issue_id" => "DEMO-16",
          "heading" => "Claude Code Workpad",
          "body" => body,
          "sections" => [
            %{"key" => "plan", "status" => "complete"},
            %{"key" => "acceptance_criteria", "status" => "complete"},
            %{"key" => "validation", "status" => "complete"}
          ]
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          cond do
            query =~ "commentCreate" ->
              assert variables == %{issueId: "DEMO-16", body: expected_body}
              {:ok, linear_comment_create_response(expected_body)}

            query =~ "commentUpdate" ->
              flunk("typed workpad upsert should create only when no active workpad exists")

            true ->
              {:ok, linear_issue_snapshot_response_with_comments([])}
          end
        end
      )

    assert_received {:linear_client_called, comments_query, %{issueId: "DEMO-16", first: 50}, []}
    assert comments_query =~ "comments"

    assert_received {:linear_client_called, create_query, %{issueId: "DEMO-16", body: ^expected_body}, []}

    assert create_query =~ "commentCreate"

    assert response["success"] == true
    assert get_in(response["payload"], ["data", "comment", "created"]) == true
    assert get_in(ReadinessStore.snapshot("DEMO-16"), ["observations", "workpad", "status"]) == "created"
    refute get_in(ReadinessStore.snapshot("DEMO-16"), ["observations", "workpad", "sections"])
  end

  test "typed linear workpad upsert reuses legacy workpad comments that are missing the heading" do
    test_pid = self()

    legacy_body = """
    ```text
    host:/workspace/repo@abc123
    ```

    ### Plan

    - [ ] Existing plan

    ### Acceptance Criteria

    - [ ] Existing criteria

    ### Validation

    - [ ] Existing validation
    """

    new_body = """
    ```text
    host:/workspace/repo@def456
    ```

    ### Plan

    - [x] Existing plan

    ### Acceptance Criteria

    - [x] Existing criteria

    ### Validation

    - [x] Existing validation
    """

    expected_body = "## Claude Code Workpad\n\n" <> String.trim(new_body)

    response =
      Bridge.execute(
        "linear_upsert_workpad",
        %{
          "issue_id" => "DEMO-16",
          "heading" => "Claude Code Workpad",
          "body" => new_body
        },
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          cond do
            query =~ "commentUpdate" ->
              assert variables == %{commentId: "comment-legacy", body: expected_body}
              {:ok, linear_comment_update_response()}

            query =~ "commentCreate" ->
              flunk("typed workpad upsert should reuse legacy workpad-shaped comments")

            true ->
              {:ok,
               linear_issue_snapshot_response_with_comments([
                 %{
                   "id" => "comment-other",
                   "body" => "normal discussion comment",
                   "resolvedAt" => nil,
                   "createdAt" => "2026-05-08T00:00:00Z",
                   "updatedAt" => "2026-05-08T00:00:00Z",
                   "user" => %{"name" => "Agent"}
                 },
                 %{
                   "id" => "comment-legacy",
                   "body" => legacy_body,
                   "resolvedAt" => nil,
                   "createdAt" => "2026-05-08T00:00:01Z",
                   "updatedAt" => "2026-05-08T00:00:01Z",
                   "user" => %{"name" => "Agent"}
                 }
               ])}
          end
        end
      )

    assert_received {:linear_client_called, _comments_query, %{issueId: "DEMO-16", first: 50}, []}

    assert_received {:linear_client_called, update_query, %{commentId: "comment-legacy", body: ^expected_body}, []}

    assert update_query =~ "commentUpdate"

    assert response["success"] == true
    assert get_in(response["payload"], ["data", "comment", "updated"]) == true
  end

  test "typed linear change proposal attachment uses GitHub PR attachment mutation" do
    test_pid = self()
    pr_url = "https://github.com/example-user/sample-repo/pull/17"

    response =
      Bridge.execute(
        "linear_attach_change_proposal",
        %{"issue_id" => "DEMO-16", "url" => pr_url, "title" => "DEMO-16 fix"},
        linear_client: fn query, variables, opts ->
          send(test_pid, {:linear_client_called, query, variables, opts})

          cond do
            query =~ "attachmentLinkGitHubPR" ->
              assert variables == %{issueId: "DEMO-16", url: pr_url, title: "DEMO-16 fix"}
              {:ok, linear_attachment_response(pr_url)}

            true ->
              {:ok, linear_issue_attachments_response([])}
          end
        end
      )

    assert_received {:linear_client_called, attachments_query, %{issueId: "DEMO-16"}, []}
    assert attachments_query =~ "attachments"

    assert_received {:linear_client_called, attach_query, %{issueId: "DEMO-16", url: ^pr_url, title: "DEMO-16 fix"}, []}

    assert attach_query =~ "attachmentLinkGitHubPR"

    assert response["success"] == true
    assert get_in(response["payload"], ["data", "attachment", "url"]) == pr_url
  end

  test "typed linear write tools are rejected by read-only side-effect policy" do
    response =
      Bridge.execute(
        "linear_move_issue",
        %{"issue_id" => "DEMO-16", "state_name" => "In Review"},
        dynamic_tool_policy: %{allowed_side_effects: ["read_only"]},
        linear_client: fn _query, _variables, _opts ->
          flunk("linear client should not be called when side-effect policy rejects the typed write tool")
        end
      )

    assert response["success"] == false

    assert response["payload"] == %{
             "error" => %{
               "message" => "Dynamic tool side-effect class is not allowed by policy.",
               "tool" => "linear_move_issue",
               "sideEffect" => "write",
               "allowedSideEffects" => ["read_only"]
             }
           }
  end

  defp linear_tool_names do
    [
      "linear_issue_snapshot",
      "linear_move_issue",
      "linear_upsert_workpad",
      "linear_attach_change_proposal",
      "linear_upsert_comment",
      "linear_prepare_file_upload",
      "linear_provider_diagnostics"
    ]
  end

  defp repo_tool_names do
    [
      "repo_checkout",
      "repo_diff",
      "repo_commit",
      "repo_push"
    ]
  end

  defp repo_provider_tool_names do
    [
      "repo_change_proposal_snapshot",
      "repo_create_or_update_change_proposal",
      "repo_read_change_proposal_discussion",
      "repo_add_change_proposal_comment",
      "repo_submit_change_proposal_review",
      "repo_reply_change_proposal_review_comment",
      "repo_read_change_proposal_checks",
      "repo_merge_change_proposal",
      "repo_close_change_proposal"
    ]
  end

  defp default_tool_names,
    do: linear_tool_names() ++ repo_tool_names() ++ repo_provider_tool_names()

  defp invalid_result_tool_context do
    %{
      source: SymphonyElixir.Tracker.DynamicToolSource,
      source_context: %{kind: "invalid_dynamic_result"},
      source_kind: "invalid_dynamic_result",
      tool_specs: [
        %{
          "name" => "typed_probe",
          "description" => "Typed probe.",
          "inputSchema" => %{"type" => "object"}
        },
        %{
          "name" => "raw_probe",
          "description" => "Raw fallback probe.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      tool_metadata: %{
        "typed_probe" => %{
          "workflowCapability" => "tracker.issue_snapshot",
          "sideEffect" => "read_only",
          "sourceKind" => "linear",
          "schemaVersion" => "1"
        },
        "raw_probe" => %{
          "sideEffect" => "destructive",
          "sourceKind" => "linear",
          "schemaVersion" => "1"
        }
      },
      tool_environment: %{}
    }
  end

  defp linear_issue_snapshot_response do
    %{
      "data" => %{
        "issue" => %{
          "id" => "issue-16",
          "identifier" => "DEMO-16",
          "title" => "Typed tool validation",
          "description" => "Validate typed tools.",
          "branchName" => "symphony/demo-16",
          "url" => "https://linear.app/test/issue/DEMO-16",
          "state" => %{"id" => "state-progress", "name" => "In Progress", "type" => "started"},
          "team" => %{
            "states" => %{
              "nodes" => [
                %{"id" => "state-progress", "name" => "In Progress", "type" => "started"},
                %{"id" => "state-review", "name" => "In Review", "type" => "unstarted"}
              ]
            }
          },
          "labels" => %{"nodes" => [%{"name" => "tooling"}]},
          "attachments" => %{"nodes" => []},
          "comments" => %{
            "nodes" => [
              %{
                "id" => "comment-1",
                "body" => "## Claude Code Workpad\n\ncurrent",
                "resolvedAt" => nil,
                "createdAt" => "2026-05-08T00:00:00Z",
                "updatedAt" => "2026-05-08T00:00:00Z",
                "user" => %{"name" => "Agent"}
              }
            ]
          }
        }
      }
    }
  end

  defp linear_issue_snapshot_response_with_comments(comments) do
    put_in(linear_issue_snapshot_response(), ["data", "issue", "comments", "nodes"], comments)
  end

  defp linear_issue_review_ready_response do
    linear_issue_snapshot_response()
    |> put_in(["data", "issue", "attachments", "nodes"], [linear_change_proposal_attachment()])
    |> put_in(["data", "issue", "comments", "nodes"], [linear_workpad_comment(linear_review_ready_workpad_body())])
  end

  defp linear_issue_review_incomplete_response do
    linear_issue_snapshot_response()
    |> put_in(["data", "issue", "attachments", "nodes"], [linear_change_proposal_attachment()])
    |> put_in(["data", "issue", "comments", "nodes"], [linear_workpad_comment(linear_review_incomplete_workpad_body())])
  end

  defp record_review_ready_evidence(issue_key) do
    ReadinessStore.record(issue_key, %{
      "observations" => %{
        "workpad" => %{
          "status" => "updated",
          "source" => "typed_tool_observed",
          "comment_id" => "comment-16",
          "updated_at" => "2026-05-19T08:06:00Z"
        },
        "repo" => %{
          "change_kind" => "code_change",
          "source" => "repo_observed",
          "head_sha" => "head-16",
          "commits" => [%{"sha" => "head-16"}]
        },
        "change_proposal" => %{
          "status" => "updated",
          "source" => "repo_provider_observed",
          "url" => "https://github.com/example-user/sample-repo/pull/17",
          "head_sha" => "head-16",
          "linked_to_tracker" => true
        },
        "validation" => %{
          "status" => "passed",
          "source" => "typed_tool_observed",
          "head_sha" => "head-16",
          "commands" => [%{"command" => "mix test", "exit_code" => 0, "head_sha" => "head-16"}]
        },
        "checks" => %{
          "status" => "passed",
          "source" => "repo_provider_observed",
          "head_sha" => "head-16"
        },
        "feedback" => %{
          "status" => "clear",
          "source" => "repo_provider_observed",
          "actionable_count" => 0
        }
      }
    })
  end

  defp linear_workpad_comment(body) do
    %{
      "id" => "comment-workpad",
      "body" => body,
      "resolvedAt" => nil,
      "createdAt" => "2026-05-08T00:00:00Z",
      "updatedAt" => "2026-05-08T01:00:00Z",
      "user" => %{"name" => "Agent"}
    }
  end

  defp linear_change_proposal_attachment do
    %{
      "id" => "attachment-pr",
      "title" => "DEMO-16 PR",
      "url" => "https://github.com/example-user/sample-repo/pull/17",
      "sourceType" => "github"
    }
  end

  defp linear_review_ready_workpad_body do
    """
    ## CodeBuddy Code Workpad

    ### Plan

    - [x] Implement the fix

    ### Acceptance Criteria

    - [x] Behavior is corrected

    ### Validation

    - [x] mix test passed
    """
  end

  defp linear_review_incomplete_workpad_body do
    """
    ## CodeBuddy Code Workpad

    ### Plan

    - [x] Reproduce the issue
    - [ ] Implement the fix

    ### Acceptance Criteria

    - [ ] Behavior is corrected

    ### Validation

    - [ ] mix test passed
    """
  end

  defp linear_issue_states_response do
    %{
      "data" => %{
        "issue" => %{
          "id" => "issue-16",
          "identifier" => "DEMO-16",
          "state" => %{"id" => "state-progress", "name" => "In Progress", "type" => "started"},
          "team" => %{
            "states" => %{
              "nodes" => [
                %{"id" => "state-progress", "name" => "In Progress", "type" => "started"},
                %{"id" => "state-review", "name" => "In Review", "type" => "unstarted"},
                %{"id" => "state-rework", "name" => "Rework", "type" => "unstarted"}
              ]
            }
          }
        }
      }
    }
  end

  defp linear_issue_update_response(state_name) do
    %{
      "data" => %{
        "issueUpdate" => %{
          "success" => true,
          "issue" => %{
            "id" => "issue-16",
            "identifier" => "DEMO-16",
            "state" => %{"id" => "state-review", "name" => state_name, "type" => "unstarted"}
          }
        }
      }
    }
  end

  defp linear_comment_update_response do
    %{
      "data" => %{
        "commentUpdate" => %{
          "success" => true,
          "comment" => %{
            "id" => "comment-1",
            "body" => "## Claude Code Workpad\n\nupdated",
            "url" => "https://linear.app/test/comment/comment-1"
          }
        }
      }
    }
  end

  defp linear_comment_create_response(body) do
    %{
      "data" => %{
        "commentCreate" => %{
          "success" => true,
          "comment" => %{
            "id" => "comment-new",
            "body" => body,
            "url" => "https://linear.app/test/comment/comment-new"
          }
        }
      }
    }
  end

  defp linear_issue_attachments_response(attachments) do
    %{"data" => %{"issue" => %{"id" => "issue-16", "attachments" => %{"nodes" => attachments}}}}
  end

  defp linear_attachment_response(url) do
    %{
      "data" => %{
        "attachmentLinkGitHubPR" => %{
          "success" => true,
          "attachment" => %{"id" => "attachment-1", "title" => "DEMO-16 fix", "url" => url}
        }
      }
    }
  end

  defp linear_file_upload_response do
    %{
      "data" => %{
        "fileUpload" => %{
          "success" => true,
          "uploadFile" => %{
            "uploadUrl" => "https://uploads.linear.app/signed/demo.mp4",
            "assetUrl" => "https://uploads.linear.app/asset/demo.mp4",
            "headers" => [
              %{"key" => "Content-Type", "value" => "video/mp4"}
            ]
          }
        }
      }
    }
  end
end
