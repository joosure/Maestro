defmodule SymphonyElixir.Observability.EventStoreTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.Observability.{EventStore, Logger}

  setup do
    {:ok, _apps} = Application.ensure_all_started(:symphony_elixir)

    EventStore.configure_from_observability(%{})
    EventStore.reset()

    on_exit(fn ->
      EventStore.configure_from_observability(%{})
      EventStore.reset()
    end)

    :ok
  end

  test "recent issue events combine issue-scoped and run-scoped structured events" do
    capture_log(fn ->
      Logger.emit(:info, :workspace_prepare_started, %{
        component: "workspace",
        issue_id: "issue-1",
        issue_identifier: "MT-1",
        run_id: "run-1"
      })

      Logger.emit(:info, :codex_session_started, %{
        component: "codex.app_server",
        run_id: "run-1",
        thread_id: "thread-1"
      })

      Logger.emit(:info, :codex_turn_started, %{
        component: "codex.app_server",
        issue_id: "issue-1",
        issue_identifier: "MT-1",
        run_id: "run-1",
        session_id: "thread-1-turn-1",
        thread_id: "thread-1",
        turn_id: "turn-1"
      })

      Logger.text(:info, "operator_only_line", %{
        component: "workspace",
        issue_id: "issue-1",
        issue_identifier: "MT-1",
        run_id: "run-1"
      })
    end)

    recent_events =
      EventStore.recent_issue_events(%{
        issue_id: "issue-1",
        issue_identifier: "MT-1",
        run_id: "run-1",
        session_id: "thread-1-turn-1"
      })

    assert Enum.map(recent_events, & &1["event"]) == [
             "codex_turn_started",
             "codex_session_started",
             "workspace_prepare_started"
           ]

    refute Enum.any?(recent_events, &(&1["message"] == "operator_only_line"))
  end

  test "codex session logs stay chronological and filter to codex-related structured events" do
    capture_log(fn ->
      Logger.emit(:info, :issue_dispatch_started, %{
        component: "orchestrator",
        issue_id: "issue-2",
        issue_identifier: "MT-2",
        run_id: "run-2"
      })

      Logger.emit(:info, :codex_session_started, %{
        component: "codex.app_server",
        run_id: "run-2",
        thread_id: "thread-2"
      })

      Logger.emit(:info, :tool_call_started, %{
        component: "agent.dynamic_tool_bridge",
        issue_id: "issue-2",
        issue_identifier: "MT-2",
        run_id: "run-2",
        session_id: "thread-2-turn-2",
        tool_name: "legacy_tracker_api"
      })

      Logger.emit(:warning, :codex_turn_failed, %{
        component: "codex.app_server",
        issue_id: "issue-2",
        issue_identifier: "MT-2",
        run_id: "run-2",
        session_id: "thread-2-turn-2",
        error: "boom"
      })
    end)

    logs =
      EventStore.agent_session_logs(%{
        issue_id: "issue-2",
        issue_identifier: "MT-2",
        run_id: "run-2",
        session_id: "thread-2-turn-2"
      })

    assert Enum.map(logs, & &1["event"]) == [
             "codex_session_started",
             "tool_call_started",
             "codex_turn_failed"
           ]

    refute Enum.any?(logs, &(&1["event"] == "issue_dispatch_started"))
  end

  test "agent session logs include provider-neutral agent lifecycle events" do
    capture_log(fn ->
      Logger.emit(:info, :agent_run_started, %{
        component: "agent_runner",
        agent_provider_kind: "fake",
        issue_id: "issue-agent",
        issue_identifier: "MT-AGENT",
        run_id: "run-agent"
      })

      Logger.emit(:info, :agent_turn_started, %{
        component: "agent_runner",
        agent_provider_kind: "fake",
        issue_id: "issue-agent",
        issue_identifier: "MT-AGENT",
        run_id: "run-agent",
        session_id: "session-agent",
        turn_number: 1,
        max_turns: 3
      })

      Logger.emit(:info, :agent_cleanup_completed, %{
        component: "agent_runner",
        agent_provider_kind: "fake",
        issue_id: "issue-agent",
        issue_identifier: "MT-AGENT",
        run_id: "run-agent",
        session_id: "session-agent"
      })

      Logger.emit(:info, :workspace_prepare_started, %{
        component: "workspace",
        issue_id: "issue-agent",
        issue_identifier: "MT-AGENT",
        run_id: "run-agent"
      })
    end)

    logs =
      EventStore.agent_session_logs(%{
        issue_id: "issue-agent",
        issue_identifier: "MT-AGENT",
        run_id: "run-agent",
        session_id: "session-agent"
      })

    assert Enum.map(logs, & &1["event"]) == [
             "agent_run_started",
             "agent_turn_started",
             "agent_cleanup_completed"
           ]
  end

  test "recent events return newest structured events across the runtime" do
    capture_log(fn ->
      Logger.emit(:info, :workflow_loaded, %{
        component: "workflow_store",
        workflow_path: "/tmp/WORKFLOW.md"
      })

      Logger.emit(:info, :workspace_prepare_started, %{
        component: "workspace",
        issue_id: "issue-3",
        issue_identifier: "MT-3",
        run_id: "run-3"
      })
    end)

    assert Enum.map(EventStore.recent_events(limit: 2), & &1["event"]) == [
             "workspace_prepare_started",
             "workflow_loaded"
           ]
  end

  test "dynamic tool usage metrics aggregate typed operator migration fallback and failure reasons" do
    capture_log(fn ->
      Logger.emit(:info, :tool_call_succeeded, %{
        component: "agent.dynamic_tool_bridge",
        run_id: "run-tools",
        session_id: "session-tools",
        tool_name: "linear_issue_snapshot",
        dynamic_tool_usage_kind: "typed",
        dynamic_tool_workflow_capability: "tracker.issue_snapshot",
        dynamic_tool_provider_capability_unavailable_count: 1,
        dynamic_tool_provider_capability_unavailable: [
          %{
            "workflowCapability" => "repo.submit_change_proposal_review",
            "reason" => "provider_capability_not_available",
            "description" => "formal PR reviews"
          }
        ]
      })

      Logger.emit(:warning, :tool_call_failed, %{
        component: "agent.dynamic_tool_bridge",
        run_id: "run-tools",
        session_id: "session-tools",
        tool_name: "legacy_tracker_api",
        dynamic_tool_usage_kind: "fallback",
        dynamic_tool_workflow_capability: "tracker.issue_snapshot",
        dynamic_tool_fallback_reason: "temporary migration",
        dynamic_tool_failure_reason: "provider_validation_failed"
      })

      Logger.emit(:warning, :tool_call_rejected, %{
        component: "agent.dynamic_tool_bridge",
        run_id: "other-run",
        session_id: "other-session",
        tool_name: "unknown_tool",
        dynamic_tool_usage_kind: "raw",
        dynamic_tool_failure_reason: "unsupported_tool"
      })
    end)

    all_metrics = EventStore.dynamic_tool_usage_metrics()

    assert all_metrics["total_calls"] == 3
    assert all_metrics["typed_calls"] == 1
    assert all_metrics["fallback_calls"] == 1
    assert all_metrics["raw_calls"] == 1
    assert all_metrics["typed_tool_hits"] == 1
    assert all_metrics["raw_tool_attempts"] == 1
    assert all_metrics["fallback_count"] == 1
    assert all_metrics["unsupported_tool_count"] == 1
    assert all_metrics["provider_capability_unavailable_count"] == 1

    assert all_metrics["provider_capability_unavailable"] == %{
             "total" => 1,
             "known" => 1,
             "unknown" => 0,
             "by_capability" => %{
               "repo.submit_change_proposal_review" => %{
                 "count" => 1,
                 "known" => true,
                 "reason" => "provider_capability_not_available",
                 "description" => "formal PR reviews"
               }
             }
           }

    assert all_metrics["operator_status"] == "critical"

    assert Enum.map(all_metrics["operator_alerts"], & &1["code"]) == [
             "raw_tool_attempts",
             "operator_migration_fallback",
             "unsupported_tool_calls",
             "provider_capability_unavailable_known"
           ]

    assert all_metrics["typed_hit_rate"] == 1 / 3
    assert all_metrics["failure_reasons"] == %{"provider_validation_failed" => 1, "unsupported_tool" => 1}
    assert get_in(all_metrics, ["by_tool", "legacy_tracker_api", "fallback_calls"]) == 1
    assert get_in(all_metrics, ["by_tool", "unknown_tool", "rejected_calls"]) == 1
    assert get_in(all_metrics, ["by_tool", "unknown_tool", "unsupported_tool_count"]) == 1
    assert get_in(all_metrics, ["by_tool", "linear_issue_snapshot", "provider_capability_unavailable", "known"]) == 1

    scoped_metrics = EventStore.dynamic_tool_usage_metrics(context: %{run_id: "run-tools"})

    assert scoped_metrics["total_calls"] == 2
    assert scoped_metrics["typed_calls"] == 1
    assert scoped_metrics["fallback_calls"] == 1
    assert scoped_metrics["raw_calls"] == 0
    assert scoped_metrics["typed_tool_hits"] == 1
    assert scoped_metrics["provider_capability_unavailable_count"] == 1
    assert scoped_metrics["operator_status"] == "warning"

    assert Enum.map(scoped_metrics["operator_alerts"], & &1["code"]) == [
             "operator_migration_fallback",
             "provider_capability_unavailable_known"
           ]

    assert scoped_metrics["failure_reasons"] == %{"provider_validation_failed" => 1}
  end

  test "reconfigure_from_observability trims buffers to configured limits" do
    EventStore.configure_from_observability(%{
      global_event_limit: 2,
      issue_event_limit: 2,
      run_event_limit: 2,
      session_event_limit: 2,
      index_key_limit: 2
    })

    capture_log(fn ->
      Logger.emit(:info, :workflow_loaded, %{component: "workflow_store"})

      Logger.emit(:info, :workspace_prepare_started, %{
        component: "workspace",
        issue_id: "issue-4",
        issue_identifier: "MT-4",
        run_id: "run-4",
        session_id: "thread-4"
      })

      Logger.emit(:info, :codex_session_started, %{
        component: "codex.app_server",
        issue_id: "issue-4",
        issue_identifier: "MT-4",
        run_id: "run-4",
        session_id: "thread-4",
        thread_id: "thread-4"
      })
    end)

    assert Enum.map(EventStore.recent_events(limit: 10), & &1["event"]) == [
             "codex_session_started",
             "workspace_prepare_started"
           ]

    assert Enum.map(
             EventStore.recent_issue_events(%{
               issue_id: "issue-4",
               issue_identifier: "MT-4",
               run_id: "run-4",
               session_id: "thread-4"
             }),
             & &1["event"]
           ) == [
             "codex_session_started",
             "workspace_prepare_started"
           ]
  end

  test "record drops events when pending event queue is full" do
    EventStore.configure_from_observability(%{
      global_event_limit: 10,
      pending_event_queue_limit: 1
    })

    :sys.suspend(EventStore)

    try do
      capture_log(fn ->
        for index <- 1..5 do
          Logger.emit(:info, :queue_pressure_event, %{
            component: "observability.event_store_test",
            result_summary: "index=#{index}"
          })
        end
      end)

      assert {:message_queue_len, length} = Process.info(Process.whereis(EventStore), :message_queue_len)
      assert length <= 1
    after
      :sys.resume(EventStore)
    end

    Process.sleep(20)

    queue_pressure_events =
      EventStore.recent_events(limit: 10)
      |> Enum.filter(&(&1["event"] == "queue_pressure_event"))

    assert length(queue_pressure_events) <= 1

    capture_log(fn ->
      Logger.emit(:info, :queue_pressure_after_resume, %{
        component: "observability.event_store_test"
      })
    end)

    assert Enum.any?(
             EventStore.recent_events(limit: 10),
             &(&1["event"] == "queue_pressure_after_resume")
           )
  end
end
