defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.TapdWorkpadRenderingSmokeTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Tapd.Adapter, as: TapdAdapter
  alias SymphonyElixir.Tracker.Tapd.CommentCodec
  alias SymphonyElixir.Tracker.WorkpadRegistry
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.WorkpadWriter

  @created_at "2026-05-20T00:00:00Z"
  @issue_id "1153000000000000420"
  @gates %{
    "workflow.structured_execution_plan.enabled" => true,
    "workflow.structured_execution_plan.render_workpad" => true
  }

  setup do
    WorkpadRegistry.reset()
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "controlled TAPD rendering smoke writes through tracker upsert workpad typed tool", %{store: store} do
    assert {:ok, _plan} = Store.create(plan(), server: store)

    test_pid = self()
    request_fun = tapd_request_fun(test_pid)

    tracker_executor = fn tool, arguments, opts ->
      TapdAdapter.execute_dynamic_tool(tapd_tracker(), tool, arguments, Keyword.put(opts, :request_fun, request_fun))
    end

    assert {:ok,
            %{
              "success" => true,
              "status" => "created",
              "tracker_tool" => "tapd_upsert_workpad",
              "workpad" => %{"id" => "tapd:issue:1153000000000000420:workpad"},
              "plan_revision" => 1,
              "stored_plan_revision" => 1,
              "rendered_workpad" => %{
                "fingerprint" => fingerprint,
                "rendered_item_count" => 2,
                "items_truncated" => false
              }
            }} =
             WorkpadWriter.write("plan-tapd-cnb-smoke-1",
               gates: @gates,
               server: store,
               tracker_comments: [],
               tracker_executor: tracker_executor,
               tracker_opts: []
             )

    assert is_binary(fingerprint)

    assert_received {:tapd_request,
                     %{
                       method: "POST",
                       url: "https://api.tapd.cn/comments",
                       params: %{
                         "entry_id" => @issue_id,
                         "entry_type" => "stories",
                         "description" => encoded_description,
                         "workspace_id" => "53000000"
                       }
                     }}

    body = CommentCodec.decode_description(encoded_description)
    assert body =~ "## Structured Execution Plan Workpad"
    assert body =~ "mode=write"
    assert body =~ "- [x] `cnb.change_proposal`"
    assert body =~ "- [ ] `cnb.checks`"
    assert body =~ "repo_create_or_update_change_proposal:1"
    assert body =~ "repo_read_change_proposal_checks:1"
    refute body =~ "https://cnb.cool/example-org/AI/sample-cnb-repo/-/pull/42"
    refute body =~ "raw_provider_payload"
    refute body =~ "provider-private-value"

    assert {:ok,
            %{
              "revision" => 1,
              "rendering" => %{
                "workpad_id" => "tapd:issue:1153000000000000420:workpad",
                "fingerprint" => ^fingerprint,
                "mode" => "write",
                "plan_revision" => 1,
                "tracker_kind" => "tapd"
              }
            }} = Store.fetch("plan-tapd-cnb-smoke-1", server: store)
  end

  defp plan do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => "plan-tapd-cnb-smoke-1",
      "run_id" => "run-tapd-cnb-smoke-1",
      "issue_id" => @issue_id,
      "tracker_kind" => "tapd",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "route_key" => "developing",
      "status" => "active",
      "items" => [
        item(
          "cnb.change_proposal",
          "complete",
          [
            evidence_ref("evidence-cnb-pr", "repo_create_or_update_change_proposal", %{
              "provider_kind" => "cnb",
              "repository" => "example-org/AI/sample-cnb-repo",
              "number" => "42",
              "url" => "https://cnb.cool/example-org/AI/sample-cnb-repo/-/pull/42",
              "raw_provider_payload" => "must-not-render"
            })
          ],
          "repo_create_or_update_change_proposal",
          ["url"]
        ),
        item(
          "cnb.checks",
          "pending",
          [
            evidence_ref("evidence-cnb-checks", "repo_read_change_proposal_checks", %{
              "provider_kind" => "cnb",
              "status" => "pending",
              "head_sha" => "abc123",
              "sensitive_field" => "provider-private-value"
            })
          ],
          "repo_read_change_proposal_checks",
          ["status"]
        )
      ],
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp item(item_id, status, evidence_refs, evidence_kind, required_fields) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => "tool_evidence",
      "status" => status,
      "required" => true,
      "criticality" => "handoff_blocking",
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => evidence_kind,
          "required_fields" => required_fields,
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => evidence_refs,
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp evidence_ref(evidence_id, evidence_kind, payload) do
    %{
      "evidence_id" => evidence_id,
      "evidence_kind" => evidence_kind,
      "source" => "tool_generated",
      "producer" => evidence_kind,
      "run_id" => "run-tapd-cnb-smoke-1",
      "issue_id" => @issue_id,
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => payload
    }
  end

  defp tapd_tracker do
    %TrackerConfig{
      kind: "tapd",
      endpoint: "https://api.tapd.cn",
      auth: %{tapd_auth_field(:user) => "tapd-user", tapd_auth_field(:credential) => "tapd-credential"},
      provider: %{"platform" => %{"workspace_id" => "53000000"}}
    }
  end

  defp tapd_auth_field(:user), do: "api_" <> "key"
  defp tapd_auth_field(:credential), do: "api_" <> "sec" <> "ret"

  defp tapd_request_fun(test_pid) do
    fn
      %{method: "GET", url: "https://api.tapd.cn/comments"} = request ->
        send(test_pid, {:tapd_request, request})

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => 1,
             "data" => []
           }
         }}

      %{method: "POST", url: "https://api.tapd.cn/comments", params: %{"id" => _comment_id}} ->
        flunk("missing rendered Workpad smoke should create, not update")

      %{method: "POST", url: "https://api.tapd.cn/comments"} = request ->
        send(test_pid, {:tapd_request, request})

        {:ok,
         %{
           status: 200,
           body: %{
             "status" => 1,
             "data" => %{
               "id" => "1153000000000000888",
               "description" => Map.fetch!(request.params, "description"),
               "url" => "https://www.tapd.cn/53000000/prong/stories/view/#{@issue_id}"
             }
           }
         }}

      request ->
        flunk("unexpected TAPD request: #{inspect(request)}")
    end
  end
end
