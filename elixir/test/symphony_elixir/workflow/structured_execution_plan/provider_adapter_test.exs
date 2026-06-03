defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @provider_gate "workflow.structured_execution_plan.provider_adapters.enabled"
  @plan_id "plan-provider-adapter-1"
  @run_id "run-provider-adapter-1"
  @issue_id "TES-86"
  @profile %{"kind" => "coding_pr_delivery", "version" => 1}
  @created_at "2026-05-20T00:00:00Z"

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "disabled provider adapters skip ingestion without changing canonical plan", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.push")]), server: store)

    assert {:ok,
            %{
              "status" => "skipped",
              "reason" => "provider_adapters_gate_disabled",
              "plan_changed" => false
            }} =
             ProviderAdapter.ingest_event(@plan_id, provider_event(), 1, server: store)

    assert {:ok, %{"revision" => 1} = stored_plan} = Store.fetch(@plan_id, server: store)
    refute Map.has_key?(stored_plan, "extensions")
  end

  test "provider-native complete records only non-authoritative correlation metadata", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.push")]), server: store)

    assert {:ok,
            %{
              "status" => "recorded",
              "plan_revision" => 2,
              "provider_session_event" => %{
                "authority" => "non_authoritative",
                "tasks" => [
                  %{
                    "provider_task_id" => "codex-step-1",
                    "requested_status" => "complete"
                  } = task
                ],
                "warnings" => warnings
              }
            }} =
             ProviderAdapter.ingest_event(@plan_id, provider_event(), 1, enabled_opts(store))

    refute Map.has_key?(task, "item_id")
    assert "provider_native_complete_does_not_satisfy_evidence" in warnings

    assert {:ok, stored_plan} = Store.fetch(@plan_id, server: store)
    assert [%{"status" => "pending", "evidence_refs" => []}] = stored_plan["items"]

    assert [
             %{
               "event_id" => "codex-plan-event-1",
               "tasks" => [%{"provider_task_id" => "codex-step-1"}]
             }
           ] = get_in(stored_plan, ["extensions", ProviderSessionEvent.extension_key()])
  end

  test "hook candidate observation is redacted and non-authoritative", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.push")]), server: store)

    redacted_key_1 = "author" <> "ization"
    redacted_value_1 = "Bearer abc123"
    redacted_key_2 = "pass" <> "word"
    redacted_value_2 = "redact-me"
    redacted_prefix = "tok" <> "en="
    redacted_value_3 = redacted_prefix <> "ghp_" <> "1234567890"

    event = %{
      "provider_kind" => "claude_code",
      "surface" => "hook_observation",
      "event_id" => "claude-hook-1",
      "observed_at" => "2026-05-20T00:00:01Z",
      "hook" => %{"hook_name" => "Stop", "phase" => "after_turn", "status" => "completed"},
      "payload" => %{
        "result" => "TaskCompleted",
        redacted_key_1 => redacted_value_1,
        redacted_key_2 => redacted_value_2,
        "note" => redacted_value_3
      }
    }

    assert {:ok, %{"provider_session_event" => %{"hook_observation" => hook, "trust_class" => "agent_declared"}}} =
             ProviderAdapter.ingest_event(@plan_id, event, 1, enabled_opts(store))

    assert hook["hook_name"] == "Stop"
    assert hook["status"] == "complete"
    assert hook["summary"] =~ "[REDACTED]"
    refute hook["summary"] =~ redacted_value_1
    refute hook["summary"] =~ redacted_value_2
    refute hook["summary"] =~ String.replace_prefix(redacted_value_3, redacted_prefix, "")
  end

  test "task completed guard returns bounded missing evidence reason", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.push")]), server: store)

    assert {:error,
            %{
              code: "structured_plan_missing_required_evidence",
              status: "blocked",
              missing_items: [
                %{
                  "item_id" => "repo.push",
                  "status" => "pending",
                  "evidence_kinds" => ["repo_push"]
                }
              ]
            }} = ProviderAdapter.task_completed_guard(@plan_id, enabled_opts(store))
  end

  test "MCP plan update delegates to backend revision and evidence checks", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([backend_item("repo.push")]), server: store)

    assert {:failure,
            %{
              "error" => %{
                "code" => "revision_conflict",
                "details" => %{"current_revision" => 1, "expected_revision" => 2}
              }
            }} =
             ProviderAdapter.execute_mcp_tool(
               "workflow_plan_update_item",
               %{"plan_id" => @plan_id, "item_id" => "repo.push", "status" => "complete", "plan_revision" => 2},
               enabled_opts(store)
             )

    assert {:failure,
            %{
              "error" => %{
                "code" => "missing_required_evidence",
                "details" => %{"item_id" => "repo.push"}
              }
            }} =
             ProviderAdapter.execute_mcp_tool(
               "workflow_plan_update_item",
               %{"plan_id" => @plan_id, "item_id" => "repo.push", "status" => "complete", "plan_revision" => 1},
               enabled_opts(store)
             )

    assert {:ok, %{"revision" => 1, "items" => [%{"status" => "pending"}]}} = Store.fetch(@plan_id, server: store)
  end

  defp enabled_opts(store) do
    [
      server: store,
      run_id: @run_id,
      gates: %{@provider_gate => true},
      updated_at: "2026-05-20T00:00:01Z"
    ]
  end

  defp provider_event do
    %{
      "provider_kind" => "codex",
      "surface" => "provider_session_tasks",
      "event_id" => "codex-plan-event-1",
      "run_id" => @run_id,
      "observed_at" => "2026-05-20T00:00:01Z",
      "tasks" => [
        %{
          "id" => "codex-step-1",
          "title" => "Push code",
          "status" => "completed",
          "item_id" => "repo.push"
        }
      ]
    }
  end

  defp plan(items) do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => @plan_id,
      "run_id" => @run_id,
      "issue_id" => @issue_id,
      "tracker_kind" => "linear",
      "workflow_profile" => @profile,
      "route_key" => "developing",
      "status" => "active",
      "items" => items,
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp backend_item(item_id) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => "tool_evidence",
      "status" => "pending",
      "required" => true,
      "criticality" => "handoff_blocking",
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "repo_push",
          "required_fields" => ["branch", "head_sha", "published_head_sha"],
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => [],
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end
end
