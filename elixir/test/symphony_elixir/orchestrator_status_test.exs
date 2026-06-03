defmodule SymphonyElixir.OrchestratorStatusTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Observability.StatusDashboard.{Presenter, PresenterOptions, Terminal, Throughput}

  @dashboard_terminal_columns 115

  defmodule MalformedSnapshotServer do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    def init(:ok), do: {:ok, :ok}

    def handle_call(:snapshot, _from, state) do
      {:reply, %{running: [], retrying: [], agent_totals: :invalid}, state}
    end
  end

  test "snapshot returns :timeout when snapshot server is unresponsive" do
    server_name = __MODULE__.UnresponsiveSnapshotServer
    parent = self()

    pid =
      spawn(fn ->
        Process.register(self(), server_name)
        send(parent, :snapshot_server_ready)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :snapshot_server_ready, 1_000
    assert Orchestrator.snapshot(server_name, 10) == :timeout

    send(pid, :stop)
  end

  test "orchestrator snapshot reflects last codex update and session id" do
    issue_id = "issue-snapshot"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-188",
      title: "Snapshot test",
      description: "Capture codex state",
      state: "In Progress",
      url: "https://example.org/issues/MT-188"
    }

    orchestrator_name = __MODULE__.SnapshotOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      turn_count: 0,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      started_at: started_at
    }

    state_with_issue =
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))

    :sys.replace_state(pid, fn _ -> state_with_issue end)

    now = DateTime.utc_now()

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :session_started,
         session_id: "thread-live-turn-live",
         timestamp: now
       }}
    )

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{method: "some-event"},
         timestamp: now
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.issue_id == issue_id
    assert snapshot_entry.session_id == "thread-live-turn-live"
    assert snapshot_entry.turn_count == 1
    assert snapshot.agent_totals == snapshot.agent_totals
    assert snapshot_entry.last_agent_timestamp == now
    assert snapshot_entry.last_agent_timestamp == now

    assert snapshot_entry.last_agent_message == %{
             event: :notification,
             message: "some-event",
             timestamp: now
           }

    assert snapshot_entry.last_agent_message == %{
             event: :notification,
             message: "some-event",
             timestamp: now
           }
  end

  test "orchestrator snapshot reflects generic agent updates while preserving codex aliases" do
    issue_id = "issue-agent-snapshot"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-AGENT",
      title: "Generic agent snapshot test",
      description: "Capture generic agent state",
      state: "In Progress",
      url: "https://example.org/issues/MT-AGENT"
    }

    orchestrator_name = __MODULE__.GenericAgentSnapshotOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      turn_count: 0,
      started_at: started_at
    }

    state_with_issue =
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))

    :sys.replace_state(pid, fn _ -> state_with_issue end)

    now = DateTime.utc_now()

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         agent_provider_kind: "fake",
         agent_process_pid: 4242,
         event: :session_started,
         payload: %{method: "turn/completed", usage: %{input_tokens: 2, output_tokens: 3, total_tokens: 5}},
         session_id: "fake-thread-fake-turn",
         timestamp: now
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.agent_provider_kind == "fake"
    assert snapshot_entry.agent_process_pid == "4242"
    assert snapshot_entry.agent_input_tokens == 2
    assert snapshot_entry.agent_output_tokens == 3
    assert snapshot_entry.agent_total_tokens == 5
    assert snapshot_entry.agent_input_tokens == 2
    assert snapshot_entry.agent_output_tokens == 3
    assert snapshot_entry.agent_total_tokens == 5
    assert snapshot_entry.last_agent_event == :session_started
    assert snapshot_entry.last_agent_event == :session_started
    assert snapshot.agent_totals.total_tokens == 5
    assert snapshot.agent_totals.total_tokens == 5
  end

  test "orchestrator snapshot tracks codex thread totals and app-server pid" do
    issue_id = "issue-usage-snapshot"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-201",
      title: "Usage snapshot test",
      description: "Collect usage stats",
      state: "In Progress",
      url: "https://example.org/issues/MT-201"
    }

    orchestrator_name = __MODULE__.UsageOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      turn_count: 0,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    now = DateTime.utc_now()

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :session_started,
         session_id: "thread-usage-turn-usage",
         timestamp: now
       }}
    )

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "thread/tokenUsage/updated",
           "params" => %{
             "tokenUsage" => %{
               "total" => %{"inputTokens" => 12, "outputTokens" => 4, "totalTokens" => 16}
             }
           }
         },
         timestamp: now,
         agent_process_pid: "4242"
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.agent_process_pid == "4242"
    assert snapshot_entry.agent_input_tokens == 12
    assert snapshot_entry.agent_output_tokens == 4
    assert snapshot_entry.agent_total_tokens == 16
    assert snapshot_entry.turn_count == 1
    assert is_integer(snapshot_entry.runtime_seconds)

    send(pid, {:DOWN, process_ref, :process, self(), :normal})
    completed_state = :sys.get_state(pid)

    assert completed_state.agent_totals.input_tokens == 12
    assert completed_state.agent_totals.output_tokens == 4
    assert completed_state.agent_totals.total_tokens == 16
    assert is_integer(completed_state.agent_totals.seconds_running)
  end

  test "orchestrator snapshot tracks turn completed usage when present" do
    issue_id = "issue-turn-completed-usage"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-202",
      title: "Turn completed usage test",
      description: "Track final turn usage",
      state: "In Progress",
      url: "https://example.org/issues/MT-202"
    }

    orchestrator_name = __MODULE__.TurnCompletedUsageOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :turn_completed,
         payload: %{
           method: "turn/completed",
           usage: %{"input_tokens" => "12", "output_tokens" => 4, "total_tokens" => 16}
         },
         timestamp: DateTime.utc_now()
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.agent_input_tokens == 12
    assert snapshot_entry.agent_output_tokens == 4
    assert snapshot_entry.agent_total_tokens == 16

    send(pid, {:DOWN, process_ref, :process, self(), :normal})
    completed_state = :sys.get_state(pid)
    assert completed_state.agent_totals.input_tokens == 12
    assert completed_state.agent_totals.output_tokens == 4
    assert completed_state.agent_totals.total_tokens == 16
  end

  test "orchestrator snapshot tracks codex token-count cumulative usage payloads" do
    issue_id = "issue-token-count-snapshot"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-220",
      title: "Token count snapshot test",
      description: "Validate token-count style payloads",
      state: "In Progress",
      url: "https://example.org/issues/MT-220"
    }

    orchestrator_name = __MODULE__.TokenCountOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    now = DateTime.utc_now()

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "codex/event/token_count",
           "params" => %{
             "msg" => %{
               "type" => "token_count",
               "info" => %{
                 "total_token_usage" => %{
                   "input_tokens" => "2",
                   "output_tokens" => 2,
                   "total_tokens" => 4
                 }
               }
             }
           }
         },
         timestamp: now
       }}
    )

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "codex/event/token_count",
           "params" => %{
             "msg" => %{
               "type" => "token_count",
               "info" => %{
                 "total_token_usage" => %{
                   "prompt_tokens" => 10,
                   "completion_tokens" => 5,
                   "total_tokens" => 15
                 }
               }
             }
           }
         },
         timestamp: DateTime.utc_now()
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.agent_input_tokens == 10
    assert snapshot_entry.agent_output_tokens == 5
    assert snapshot_entry.agent_total_tokens == 15

    send(pid, {:DOWN, process_ref, :process, self(), :normal})
    completed_state = :sys.get_state(pid)

    assert completed_state.agent_totals.input_tokens == 10
    assert completed_state.agent_totals.output_tokens == 5
    assert completed_state.agent_totals.total_tokens == 15
  end

  test "orchestrator snapshot tracks codex rate-limit payloads" do
    issue_id = "issue-rate-limit-snapshot"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-221",
      title: "Rate limit snapshot test",
      description: "Capture codex rate limit state",
      state: "In Progress",
      url: "https://example.org/issues/MT-221"
    }

    orchestrator_name = __MODULE__.RateLimitOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    rate_limits = %{
      "limit_id" => "codex",
      "primary" => %{"remaining" => 90, "limit" => 100},
      "secondary" => nil,
      "credits" => %{"has_credits" => false, "unlimited" => false, "balance" => nil}
    }

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "codex/event/token_count",
           "params" => %{
             "msg" => %{
               "type" => "event_msg",
               "payload" => %{
                 "type" => "token_count",
                 "rate_limits" => rate_limits
               }
             }
           }
         },
         timestamp: DateTime.utc_now()
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert snapshot.agent_rate_limits == rate_limits
  end

  test "orchestrator snapshot tracks camelCase codex account rate-limit payloads" do
    issue_id = "issue-camel-rate-limit-snapshot"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-223",
      title: "Camel case rate limit snapshot test",
      description: "Capture codex account rate limit state",
      state: "In Progress",
      url: "https://example.org/issues/MT-223"
    }

    orchestrator_name = __MODULE__.CamelCaseRateLimitOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    rate_limits = %{
      "limitId" => "codex",
      "limitName" => nil,
      "primary" => nil,
      "secondary" => nil,
      "credits" => nil,
      "planType" => nil
    }

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "account/rateLimits/updated",
           "params" => %{"rateLimits" => rate_limits}
         },
         timestamp: DateTime.utc_now()
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert snapshot.agent_rate_limits == rate_limits
  end

  test "orchestrator token accounting prefers total_token_usage over last_token_usage in token_count payloads" do
    issue_id = "issue-token-precedence"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-222",
      title: "Token precedence",
      description: "Prefer per-event deltas",
      state: "In Progress",
      url: "https://example.org/issues/MT-222"
    }

    orchestrator_name = __MODULE__.TokenPrecedenceOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "codex/event/token_count",
           "params" => %{
             "msg" => %{
               "type" => "event_msg",
               "payload" => %{
                 "type" => "token_count",
                 "info" => %{
                   "last_token_usage" => %{
                     "input_tokens" => 2,
                     "output_tokens" => 1,
                     "total_tokens" => 3
                   },
                   "total_token_usage" => %{
                     "input_tokens" => 200,
                     "output_tokens" => 100,
                     "total_tokens" => 300
                   }
                 }
               }
             }
           }
         },
         timestamp: DateTime.utc_now()
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.agent_input_tokens == 200
    assert snapshot_entry.agent_output_tokens == 100
    assert snapshot_entry.agent_total_tokens == 300
  end

  test "orchestrator token accounting accumulates monotonic thread token usage totals" do
    issue_id = "issue-thread-token-usage"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-223",
      title: "Thread token usage",
      description: "Accumulate absolute thread totals",
      state: "In Progress",
      url: "https://example.org/issues/MT-223"
    }

    orchestrator_name = __MODULE__.ThreadTokenUsageOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    for usage <- [
          %{"input_tokens" => 8, "output_tokens" => 3, "total_tokens" => 11},
          %{"input_tokens" => 10, "output_tokens" => 4, "total_tokens" => 14}
        ] do
      send(
        pid,
        {:agent_worker_update, issue_id,
         %{
           event: :notification,
           payload: %{
             "method" => "thread/tokenUsage/updated",
             "params" => %{"tokenUsage" => %{"total" => usage}}
           },
           timestamp: DateTime.utc_now()
         }}
      )
    end

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.agent_input_tokens == 10
    assert snapshot_entry.agent_output_tokens == 4
    assert snapshot_entry.agent_total_tokens == 14
  end

  test "orchestrator token accounting ignores last_token_usage without cumulative totals" do
    issue_id = "issue-last-token-ignored"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-224",
      title: "Last token ignored",
      description: "Ignore delta-only token reports",
      state: "In Progress",
      url: "https://example.org/issues/MT-224"
    }

    orchestrator_name = __MODULE__.LastTokenIgnoredOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "codex/event/token_count",
           "params" => %{
             "msg" => %{
               "type" => "event_msg",
               "payload" => %{
                 "type" => "token_count",
                 "info" => %{
                   "last_token_usage" => %{
                     "input_tokens" => 8,
                     "output_tokens" => 3,
                     "total_tokens" => 11
                   }
                 }
               }
             }
           }
         },
         timestamp: DateTime.utc_now()
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.agent_input_tokens == 0
    assert snapshot_entry.agent_output_tokens == 0
    assert snapshot_entry.agent_total_tokens == 0
  end

  test "orchestrator snapshot includes retry backoff entries" do
    orchestrator_name = __MODULE__.RetryOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    retry_entry = %{
      attempt: 2,
      timer_ref: nil,
      due_at_ms: System.monotonic_time(:millisecond) + 5_000,
      identifier: "MT-500",
      error: "agent exited: :boom"
    }

    initial_state = :sys.get_state(pid)
    new_state = %{initial_state | retry_attempts: %{"mt-500" => retry_entry}}
    :sys.replace_state(pid, fn _ -> new_state end)

    snapshot = GenServer.call(pid, :snapshot)
    assert is_list(snapshot.retrying)

    assert [
             %{
               issue_id: "mt-500",
               attempt: 2,
               due_in_ms: due_in_ms,
               identifier: "MT-500",
               error: "agent exited: :boom"
             }
           ] = snapshot.retrying

    assert due_in_ms > 0
  end

  test "orchestrator snapshot excludes internal continuation timers from retry backoff" do
    orchestrator_name = __MODULE__.ContinuationSnapshotOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    retry_entry = %{
      attempt: 1,
      timer_ref: nil,
      due_at_ms: System.monotonic_time(:millisecond) + 1_000,
      identifier: "MEM-1",
      error: nil,
      delay_type: :continuation
    }

    initial_state = :sys.get_state(pid)
    new_state = %{initial_state | retry_attempts: %{"local-memory-1" => retry_entry}}
    :sys.replace_state(pid, fn _ -> new_state end)

    snapshot = GenServer.call(pid, :snapshot)

    assert snapshot.retrying == []
  end

  test "orchestrator snapshot includes poll countdown and checking status" do
    orchestrator_name = __MODULE__.PollingSnapshotOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    now_ms = System.monotonic_time(:millisecond)

    :sys.replace_state(pid, fn state ->
      %{
        state
        | poll_interval_ms: 30_000,
          tick_timer_ref: nil,
          tick_token: make_ref(),
          next_poll_due_at_ms: now_ms + 4_000,
          poll_check_in_progress: false
      }
    end)

    snapshot = GenServer.call(pid, :snapshot)

    assert %{
             polling: %{
               checking?: false,
               poll_interval_ms: 30_000,
               next_poll_in_ms: due_in_ms
             }
           } = snapshot

    assert is_integer(due_in_ms)
    assert due_in_ms >= 0
    assert due_in_ms <= 4_000

    :sys.replace_state(pid, fn state ->
      %{state | poll_check_in_progress: true, next_poll_due_at_ms: nil}
    end)

    snapshot = GenServer.call(pid, :snapshot)
    assert %{polling: %{checking?: true, next_poll_in_ms: nil}} = snapshot
  end

  test "orchestrator triggers an immediate poll cycle shortly after startup" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: nil,
      poll_interval_ms: 5_000
    )

    orchestrator_name = __MODULE__.ImmediateStartupOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    assert %{polling: %{checking?: true}} =
             wait_for_snapshot(
               pid,
               fn
                 %{polling: %{checking?: true}} ->
                   true

                 _ ->
                   false
               end,
               500
             )

    assert %{
             polling: %{
               checking?: false,
               next_poll_in_ms: next_poll_in_ms,
               poll_interval_ms: 5_000
             }
           } =
             wait_for_snapshot(
               pid,
               fn
                 %{polling: %{checking?: false, next_poll_in_ms: due_in_ms}}
                 when is_integer(due_in_ms) and due_in_ms <= 5_000 ->
                   true

                 _ ->
                   false
               end,
               500
             )

    assert is_integer(next_poll_in_ms)
    assert next_poll_in_ms >= 0
  end

  test "orchestrator poll cycle resets next refresh countdown after a check" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: nil,
      poll_interval_ms: 50
    )

    orchestrator_name = __MODULE__.PollCycleOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    :sys.replace_state(pid, fn state ->
      %{
        state
        | poll_interval_ms: 50,
          poll_check_in_progress: true,
          next_poll_due_at_ms: nil
      }
    end)

    send(pid, :run_poll_cycle)

    snapshot =
      wait_for_snapshot(pid, fn
        %{polling: %{checking?: false, poll_interval_ms: 50, next_poll_in_ms: next_poll_in_ms}}
        when is_integer(next_poll_in_ms) and next_poll_in_ms <= 50 ->
          true

        _ ->
          false
      end)

    assert %{
             polling: %{
               checking?: false,
               poll_interval_ms: 50,
               next_poll_in_ms: next_poll_in_ms
             }
           } = snapshot

    assert is_integer(next_poll_in_ms)
    assert next_poll_in_ms >= 0
    assert next_poll_in_ms <= 50
  end

  test "orchestrator restarts stalled workers with retry backoff" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: nil,
      agent_provider_options: %{stall_timeout_ms: 1_000}
    )

    issue_id = "issue-stall"
    orchestrator_name = __MODULE__.StallOrchestrator
    {:ok, pid} = start_orchestrator(orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    worker_pid =
      spawn(fn ->
        receive do
          :done -> :ok
        end
      end)

    stale_activity_at = DateTime.add(DateTime.utc_now(), -5, :second)
    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: worker_pid,
      ref: make_ref(),
      identifier: "MT-STALL",
      issue: %Issue{id: issue_id, identifier: "MT-STALL", state: "In Progress"},
      session_id: "thread-stall-turn-stall",
      last_agent_message: nil,
      last_agent_timestamp: stale_activity_at,
      last_agent_event: :notification,
      started_at: stale_activity_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    log =
      capture_log(fn ->
        send(pid, :tick)
        Process.sleep(100)
      end)

    state = :sys.get_state(pid)

    refute Process.alive?(worker_pid)
    refute Map.has_key?(state.running, issue_id)

    assert %{
             attempt: 1,
             due_at_ms: due_at_ms,
             identifier: "MT-STALL",
             error: "stalled for " <> _
           } = state.retry_attempts[issue_id]

    assert is_integer(due_at_ms)
    remaining_ms = due_at_ms - System.monotonic_time(:millisecond)
    assert remaining_ms >= 9_500
    assert remaining_ms <= 10_500
    assert log =~ "issue_stall_detected"
    assert log =~ "issue_retry_scheduled"
    assert log =~ "agent_run_retry_scheduled"
  end

  test "reconcile keeps recently active workers alive during bounded non-active completion grace" do
    issue_id = "issue-non-active-grace"
    active_at = DateTime.utc_now()

    worker_pid =
      spawn(fn ->
        receive do
          :done -> :ok
        end
      end)

    on_exit(fn ->
      if Process.alive?(worker_pid) do
        Process.exit(worker_pid, :kill)
      end
    end)

    running_entry = %{
      pid: worker_pid,
      ref: make_ref(),
      identifier: "MT-GRACE",
      issue: %Issue{id: issue_id, identifier: "MT-GRACE", state: "In Progress"},
      session_id: "thread-grace-turn-grace",
      last_agent_message: nil,
      last_agent_timestamp: active_at,
      last_agent_event: :stream_output,
      started_at: active_at
    }

    state = %{
      running: %{issue_id => running_entry},
      claimed: MapSet.new([issue_id]),
      retry_attempts: %{}
    }

    review_issue = %Issue{id: issue_id, identifier: "MT-GRACE", state: "Review"}

    dispatch_context =
      SymphonyElixir.Orchestrator.Dispatch.new_context(["In Progress"], ["Done"])

    opts = [
      now: active_at,
      completion_grace_ms: 5_000,
      record_session_completion_totals: fn state, _running_entry -> state end
    ]

    state_with_grace =
      SymphonyElixir.Orchestrator.Running.reconcile_issue_states(
        [review_issue],
        state,
        dispatch_context,
        opts
      )

    assert Process.alive?(worker_pid)

    assert %{^issue_id => %{completion_grace_observed_at: ^active_at, issue: %{state: "Review"}}} =
             state_with_grace.running

    final_state =
      SymphonyElixir.Orchestrator.Running.reconcile_issue_states(
        [review_issue],
        state_with_grace,
        dispatch_context,
        Keyword.put(opts, :now, DateTime.add(active_at, 6, :second))
      )

    assert wait_for_process_exit(worker_pid)
    refute Map.has_key?(final_state.running, issue_id)
    refute MapSet.member?(final_state.claimed, issue_id)
  end

  test "reconcile keeps recently active terminal workers alive during bounded completion grace" do
    issue_id = "issue-terminal-grace"
    active_at = DateTime.utc_now()
    parent = self()

    worker_pid =
      spawn(fn ->
        receive do
          :done -> :ok
        end
      end)

    on_exit(fn ->
      if Process.alive?(worker_pid) do
        Process.exit(worker_pid, :kill)
      end
    end)

    running_entry = %{
      pid: worker_pid,
      ref: make_ref(),
      identifier: "MT-DONE",
      issue: %Issue{id: issue_id, identifier: "MT-DONE", state: "Merging"},
      session_id: "thread-terminal-turn-grace",
      last_agent_message: nil,
      last_agent_timestamp: active_at,
      last_agent_event: :tool_call_completed,
      started_at: active_at
    }

    state = %{
      running: %{issue_id => running_entry},
      claimed: MapSet.new([issue_id]),
      retry_attempts: %{}
    }

    done_issue = %Issue{id: issue_id, identifier: "MT-DONE", state: "Done"}

    dispatch_context =
      SymphonyElixir.Orchestrator.Dispatch.new_context(["In Progress", "Merging"], ["Done"])

    opts = [
      now: active_at,
      completion_grace_ms: 5_000,
      cleanup_issue_workspace: fn identifier, worker_host, workspace_path ->
        send(parent, {:cleanup_workspace, identifier, worker_host, workspace_path})
        :ok
      end,
      record_session_completion_totals: fn state, _running_entry -> state end
    ]

    state_with_grace =
      SymphonyElixir.Orchestrator.Running.reconcile_issue_states(
        [done_issue],
        state,
        dispatch_context,
        opts
      )

    assert Process.alive?(worker_pid)
    refute_received {:cleanup_workspace, _, _, _}

    assert %{^issue_id => %{completion_grace_observed_at: ^active_at, issue: %{state: "Done"}}} =
             state_with_grace.running

    final_state =
      SymphonyElixir.Orchestrator.Running.reconcile_issue_states(
        [done_issue],
        state_with_grace,
        dispatch_context,
        Keyword.put(opts, :now, DateTime.add(active_at, 6, :second))
      )

    assert wait_for_process_exit(worker_pid)
    assert_received {:cleanup_workspace, "MT-DONE", nil, nil}
    refute Map.has_key?(final_state.running, issue_id)
    refute MapSet.member?(final_state.claimed, issue_id)
  end

  test "reconcile follows dispatch context for terminal completion grace" do
    issue_id = "issue-custom-terminal-grace"
    active_at = DateTime.utc_now()

    worker_pid =
      spawn(fn ->
        receive do
          :done -> :ok
        end
      end)

    on_exit(fn ->
      if Process.alive?(worker_pid) do
        Process.exit(worker_pid, :kill)
      end
    end)

    running_entry = %{
      pid: worker_pid,
      ref: make_ref(),
      identifier: "MT-CUSTOM",
      issue: %Issue{id: issue_id, identifier: "MT-CUSTOM", state: "Building"},
      session_id: "thread-custom-terminal-grace",
      last_agent_message: nil,
      last_agent_timestamp: active_at,
      last_agent_event: :tool_call_completed,
      started_at: active_at
    }

    state = %{
      running: %{issue_id => running_entry},
      claimed: MapSet.new([issue_id]),
      retry_attempts: %{}
    }

    accepted_issue = %Issue{id: issue_id, identifier: "MT-CUSTOM", state: "Accepted"}

    dispatch_context =
      SymphonyElixir.Orchestrator.Dispatch.new_context(["Building"], ["Accepted"])

    opts = [
      now: active_at,
      completion_grace_ms: 5_000,
      record_session_completion_totals: fn state, _running_entry -> state end
    ]

    state_with_grace =
      SymphonyElixir.Orchestrator.Running.reconcile_issue_states(
        [accepted_issue],
        state,
        dispatch_context,
        opts
      )

    assert Process.alive?(worker_pid)

    assert %{
             ^issue_id => %{
               completion_grace_observed_at: ^active_at,
               issue: %{state: "Accepted"}
             }
           } = state_with_grace.running

    final_state =
      SymphonyElixir.Orchestrator.Running.reconcile_issue_states(
        [accepted_issue],
        state_with_grace,
        dispatch_context,
        Keyword.put(opts, :now, DateTime.add(active_at, 6, :second))
      )

    assert wait_for_process_exit(worker_pid)
    refute Map.has_key?(final_state.running, issue_id)
    refute MapSet.member?(final_state.claimed, issue_id)
  end

  test "normal worker exit suppresses continuation after refreshed terminal state" do
    issue_id = "issue-terminal-normal-exit"
    ref = make_ref()
    now = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: ref,
      run_id: "run-terminal-normal-exit",
      identifier: "MT-DONE-NORMAL",
      issue: %Issue{id: issue_id, identifier: "MT-DONE-NORMAL", state: "Done"},
      worker_host: nil,
      workspace_path: nil,
      session_id: "thread-terminal-normal-exit",
      agent_provider_kind: "mock",
      failure_class: nil,
      started_at: now
    }

    state =
      SymphonyElixir.Orchestrator.State.initial()
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))

    assert {:noreply, final_state} =
             SymphonyElixir.Orchestrator.WorkerExit.handle_down_message(state, ref, :normal, [])

    refute Map.has_key?(final_state.running, issue_id)
    refute Map.has_key?(final_state.retry_attempts, issue_id)
    refute MapSet.member?(final_state.claimed, issue_id)
    assert MapSet.member?(final_state.completed, issue_id)
  end

  test "normal worker exit refreshes stale running issue before scheduling continuation" do
    issue_id = "issue-stale-terminal-normal-exit"
    ref = make_ref()
    now = DateTime.utc_now()
    parent = self()

    stale_issue = %Issue{id: issue_id, identifier: "MT-STALE-DONE", state: "In Progress"}
    terminal_issue = %Issue{stale_issue | state: "Done"}

    running_entry = %{
      pid: self(),
      ref: ref,
      run_id: "run-stale-terminal-normal-exit",
      identifier: "MT-STALE-DONE",
      issue: stale_issue,
      worker_host: nil,
      workspace_path: nil,
      session_id: "thread-stale-terminal-normal-exit",
      agent_provider_kind: "mock",
      failure_class: nil,
      started_at: now
    }

    state =
      SymphonyElixir.Orchestrator.State.initial()
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))

    fetch_issue_states_by_ids = fn [^issue_id] ->
      send(parent, {:worker_exit_issue_refresh, issue_id})
      {:ok, [terminal_issue]}
    end

    log =
      capture_log(fn ->
        result =
          SymphonyElixir.Orchestrator.WorkerExit.handle_down_message(
            state,
            ref,
            :normal,
            fetch_issue_states_by_ids: fetch_issue_states_by_ids
          )

        send(parent, {:worker_exit_result, result})
      end)

    assert_receive {:worker_exit_issue_refresh, ^issue_id}
    assert_receive {:worker_exit_result, {:noreply, final_state}}

    refute Map.has_key?(final_state.running, issue_id)
    refute Map.has_key?(final_state.retry_attempts, issue_id)
    refute MapSet.member?(final_state.claimed, issue_id)
    assert MapSet.member?(final_state.completed, issue_id)
    assert log =~ "agent_run_continuation_suppressed"
    assert log =~ "current_state=\"Done\""
    refute log =~ "result=continuation_scheduled"
    refute log =~ "issue_retry_scheduled"
  end

  test "worker exit options inject bounded issue-state refresh" do
    opts = SymphonyElixir.Orchestrator.ServerOptions.worker_exit_opts()

    assert is_function(Keyword.fetch!(opts, :fetch_issue_states_by_ids), 1)
    assert Keyword.fetch!(opts, :issue_refresh_timeout_ms) == 2_000
    assert Keyword.fetch!(opts, :issue_fact_freshness_ms) == 10_000
  end

  test "normal worker exit uses fresh runtime issue fact without tracker refresh" do
    issue_id = "issue-runtime-fact-terminal"
    ref = make_ref()
    now = DateTime.utc_now()
    now_ms = System.monotonic_time(:millisecond)
    parent = self()

    running_entry = %{
      pid: self(),
      ref: ref,
      run_id: "run-runtime-fact-terminal",
      identifier: "MT-RUNTIME-FACT",
      issue: %Issue{id: issue_id, identifier: "MT-RUNTIME-FACT", state: "In Progress"},
      worker_host: nil,
      workspace_path: nil,
      session_id: "thread-runtime-fact-terminal",
      agent_provider_kind: "mock",
      failure_class: nil,
      started_at: now
    }

    terminal_issue = %Issue{id: issue_id, identifier: "MT-RUNTIME-FACT", state: "Done"}

    state =
      SymphonyElixir.Orchestrator.State.initial()
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))
      |> SymphonyElixir.Orchestrator.AgentUpdates.worker_runtime_info(issue_id, %{
        issue: terminal_issue,
        issue_fact_source: :agent_turn_refresh,
        monotonic_ms: now_ms
      })

    fetch_issue_states_by_ids = fn [^issue_id] ->
      send(parent, {:unexpected_worker_exit_refresh, issue_id})
      {:ok, [running_entry.issue]}
    end

    log =
      capture_log(fn ->
        result =
          SymphonyElixir.Orchestrator.WorkerExit.handle_down_message(
            state,
            ref,
            :normal,
            fetch_issue_states_by_ids: fetch_issue_states_by_ids,
            issue_fact_freshness_ms: 1_000,
            monotonic_ms: now_ms + 1
          )

        send(parent, {:worker_exit_result, result})
      end)

    refute_receive {:unexpected_worker_exit_refresh, ^issue_id}, 50
    assert_receive {:worker_exit_result, {:noreply, final_state}}

    refute Map.has_key?(final_state.running, issue_id)
    refute Map.has_key?(final_state.retry_attempts, issue_id)
    refute MapSet.member?(final_state.claimed, issue_id)
    assert MapSet.member?(final_state.completed, issue_id)
    assert log =~ "agent_run_continuation_suppressed"
    assert log =~ "current_state=\"Done\""
    refute log =~ "worker_exit_issue_refresh_failed"
    refute log =~ "result=continuation_scheduled"
  end

  test "normal worker exit bounds stale issue refresh before falling back to cached state" do
    issue_id = "issue-stale-refresh-timeout"
    ref = make_ref()
    now = DateTime.utc_now()
    parent = self()

    stale_issue = %Issue{id: issue_id, identifier: "MT-STALE-TIMEOUT", state: "In Progress"}
    terminal_issue = %Issue{stale_issue | state: "Done"}

    running_entry = %{
      pid: self(),
      ref: ref,
      run_id: "run-stale-refresh-timeout",
      identifier: "MT-STALE-TIMEOUT",
      issue: stale_issue,
      worker_host: nil,
      workspace_path: nil,
      session_id: "thread-stale-refresh-timeout",
      agent_provider_kind: "mock",
      failure_class: nil,
      started_at: now
    }

    state =
      SymphonyElixir.Orchestrator.State.initial()
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.new([issue_id]))

    fetch_issue_states_by_ids = fn [^issue_id] ->
      send(parent, {:worker_exit_issue_refresh_started, issue_id})
      Process.sleep(200)
      {:ok, [terminal_issue]}
    end

    started_at_ms = System.monotonic_time(:millisecond)

    log =
      capture_log(fn ->
        result =
          SymphonyElixir.Orchestrator.WorkerExit.handle_down_message(
            state,
            ref,
            :normal,
            fetch_issue_states_by_ids: fetch_issue_states_by_ids,
            issue_refresh_timeout_ms: 10
          )

        send(parent, {:worker_exit_result, result})
      end)

    elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms

    assert_receive {:worker_exit_issue_refresh_started, ^issue_id}
    assert_receive {:worker_exit_result, {:noreply, final_state}}
    assert elapsed_ms < 500

    refute Map.has_key?(final_state.running, issue_id)
    assert MapSet.member?(final_state.completed, issue_id)
    assert %{attempt: 1} = final_state.retry_attempts[issue_id]
    assert log =~ "worker_exit_issue_refresh_failed"
    assert log =~ "worker_exit_issue_refresh_timeout"
    assert log =~ "result=continuation_scheduled"
  end

  test "reconcile terminates non-active workers immediately when agent activity is stale" do
    issue_id = "issue-non-active-stale"
    active_at = DateTime.add(DateTime.utc_now(), -20, :second)

    worker_pid =
      spawn(fn ->
        receive do
          :done -> :ok
        end
      end)

    on_exit(fn ->
      if Process.alive?(worker_pid) do
        Process.exit(worker_pid, :kill)
      end
    end)

    running_entry = %{
      pid: worker_pid,
      ref: make_ref(),
      identifier: "MT-STALE",
      issue: %Issue{id: issue_id, identifier: "MT-STALE", state: "In Progress"},
      session_id: "thread-stale-turn-stale",
      last_agent_message: nil,
      last_agent_timestamp: active_at,
      last_agent_event: :notification,
      started_at: active_at
    }

    state = %{
      running: %{issue_id => running_entry},
      claimed: MapSet.new([issue_id]),
      retry_attempts: %{}
    }

    review_issue = %Issue{id: issue_id, identifier: "MT-STALE", state: "Review"}

    dispatch_context =
      SymphonyElixir.Orchestrator.Dispatch.new_context(["In Progress"], ["Done"])

    final_state =
      SymphonyElixir.Orchestrator.Running.reconcile_issue_states(
        [review_issue],
        state,
        dispatch_context,
        now: DateTime.utc_now(),
        completion_grace_ms: 5_000,
        record_session_completion_totals: fn state, _running_entry -> state end
      )

    assert wait_for_process_exit(worker_pid)
    refute Map.has_key?(final_state.running, issue_id)
    refute MapSet.member?(final_state.claimed, issue_id)
  end

  test "status dashboard renders offline marker to terminal" do
    rendered =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = StatusDashboard.render_offline_status()
      end)

    assert rendered =~ "app_status=offline"
    refute rendered =~ "Timestamp:"
  end

  test "status dashboard emits structured offline render failure events" do
    log =
      capture_log(fn ->
        assert :ok =
                 Terminal.render_offline_status(fn _content ->
                   raise ArgumentError, "offline boom"
                 end)
      end)

    assert log =~ "dashboard_offline_render_failed"
    assert log =~ "offline boom"
  end

  test "status dashboard renders linear project link in header" do
    snapshot_data =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: nil
       }}

    rendered = format_dashboard_snapshot(snapshot_data, 0.0)

    assert rendered =~ "https://linear.app/project/project/issues"
    refute rendered =~ "Dashboard:"
  end

  test "status dashboard renders camelCase rate limit identifiers instead of unavailable" do
    snapshot_data =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: %{
           "limitId" => "codex",
           "limitName" => nil,
           "primary" => nil,
           "secondary" => nil,
           "credits" => nil,
           "planType" => nil
         }
       }}

    rendered = format_dashboard_snapshot(snapshot_data, 0.0)
    plain = Regex.replace(~r/\e\[[0-9;]*m/, rendered, "")

    assert plain =~ "Rate Limits: codex | primary n/a | secondary n/a | credits n/a"
    refute plain =~ "Rate Limits: unavailable"
  end

  test "status dashboard renders dashboard url on its own line when server port is configured" do
    previous_port_override = Application.get_env(:symphony_elixir, :server_port_override)

    on_exit(fn ->
      if is_nil(previous_port_override) do
        Application.delete_env(:symphony_elixir, :server_port_override)
      else
        Application.put_env(:symphony_elixir, :server_port_override, previous_port_override)
      end
    end)

    Application.put_env(:symphony_elixir, :server_port_override, 4000)

    snapshot_data =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: nil
       }}

    rendered = format_dashboard_snapshot(snapshot_data, 0.0)

    assert rendered =~ "│ Project:"
    assert rendered =~ "https://linear.app/project/project/issues"
    assert rendered =~ "│ Dashboard:"
    assert rendered =~ "http://127.0.0.1:4000/"
  end

  test "status dashboard prefers the bound server port and normalizes wildcard hosts" do
    assert PresenterOptions.dashboard_url("0.0.0.0", 0, 43_123) ==
             "http://127.0.0.1:43123/"

    assert PresenterOptions.dashboard_url("::1", 4000, nil) ==
             "http://[::1]:4000/"
  end

  test "status dashboard renders next refresh countdown and checking marker" do
    waiting_snapshot =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: nil,
         polling: %{checking?: false, next_poll_in_ms: 2_000, poll_interval_ms: 30_000}
       }}

    waiting_rendered = format_dashboard_snapshot(waiting_snapshot, 0.0)
    assert waiting_rendered =~ "Next refresh:"
    assert waiting_rendered =~ "2s"

    checking_snapshot =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: nil,
         polling: %{checking?: true, next_poll_in_ms: nil, poll_interval_ms: 30_000}
       }}

    checking_rendered = format_dashboard_snapshot(checking_snapshot, 0.0)
    assert checking_rendered =~ "checking now…"
  end

  test "status dashboard adds a spacer line before backoff queue when no agents are active" do
    snapshot_data =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: nil
       }}

    rendered = format_dashboard_snapshot(snapshot_data, 0.0)
    plain = Regex.replace(~r/\e\[[0-9;]*m/, rendered, "")

    assert plain =~ ~r/No active agents\r?\n│\s*\r?\n├─ Backoff queue/
  end

  test "status dashboard adds a spacer line before backoff queue when agents are active" do
    snapshot_data =
      {:ok,
       %{
         running: [
           %{
             identifier: "MT-777",
             state: "running",
             session_id: "thread-1234567890",
             agent_process_pid: "4242",
             agent_total_tokens: 3_200,
             runtime_seconds: 75,
             turn_count: 7,
             last_agent_event: "turn_completed",
             last_agent_message: %{
               event: :notification,
               message: %{
                 "method" => "turn/completed",
                 "params" => %{"turn" => %{"status" => "completed"}}
               }
             }
           }
         ],
         retrying: [],
         agent_totals: %{
           input_tokens: 90,
           output_tokens: 12,
           total_tokens: 102,
           seconds_running: 75
         },
         agent_rate_limits: nil
       }}

    rendered = format_dashboard_snapshot(snapshot_data, 0.0)
    plain = Regex.replace(~r/\e\[[0-9;]*m/, rendered, "")

    assert plain =~ ~r/MT-777.*\r?\n│\s*\r?\n├─ Backoff queue/s
  end

  test "status dashboard renders issue drill-down summaries when structured history is available" do
    snapshot_data =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: nil,
         drilldown: [
           %{
             issue_identifier: "MT-DRILL",
             state: "In Progress",
             run_id: "run-123",
             session_id: "thread-1234567890",
             recent_events: [
               %{"event" => "workspace_prepare_started"},
               %{"event" => "codex_turn_started"}
             ],
             agent_session_logs: [
               %{"event" => "codex_session_started"},
               %{"event" => "codex_turn_completed"}
             ]
           }
         ]
       }}

    rendered = format_dashboard_snapshot(snapshot_data, 0.0)
    plain = Regex.replace(~r/\e\[[0-9;]*m/, rendered, "")

    assert plain =~ "├─ Issue drill-down"
    assert plain =~ "MT-DRILL [In Progress] run=run-123 session=thre...567890"
    assert plain =~ "recent: workspace_prepare_started -> codex_turn_started"
    assert plain =~ "agent : codex_session_started -> codex_turn_completed"
  end

  test "status dashboard renders an unstyled closing corner when the retry queue is empty" do
    snapshot_data =
      {:ok,
       %{
         running: [],
         retrying: [],
         agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         agent_rate_limits: nil
       }}

    rendered = format_dashboard_snapshot(snapshot_data, 0.0)

    assert rendered |> String.split("\n") |> List.last() == "╰─"
  end

  test "status dashboard coalesces rapid updates to one render per interval" do
    dashboard_name = __MODULE__.RenderDashboard
    parent = self()
    orchestrator_pid = Process.whereis(SymphonyElixir.Orchestrator)

    on_exit(fn ->
      if is_nil(Process.whereis(SymphonyElixir.Orchestrator)) do
        case Process.whereis(SymphonyElixir.Supervisor) do
          pid when is_pid(pid) ->
            case Supervisor.restart_child(SymphonyElixir.Supervisor, SymphonyElixir.Orchestrator) do
              {:ok, _pid} -> :ok
              {:error, {:already_started, _pid}} -> :ok
              {:error, :running} -> :ok
            end

          _ ->
            :ok
        end
      end
    end)

    if is_pid(orchestrator_pid) do
      assert :ok = Supervisor.terminate_child(SymphonyElixir.Supervisor, SymphonyElixir.Orchestrator)
    end

    {:ok, pid} =
      StatusDashboard.start_link(
        name: dashboard_name,
        enabled: true,
        refresh_ms: 60_000,
        render_interval_ms: 16,
        render_fun: fn content ->
          send(parent, {:render, System.monotonic_time(:millisecond), content})
        end
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    StatusDashboard.notify_update(dashboard_name)
    assert_receive {:render, first_render_ms, _content}, 200

    :sys.replace_state(pid, fn state ->
      %{state | last_snapshot_fingerprint: :force_next_change, last_rendered_content: nil}
    end)

    StatusDashboard.notify_update(dashboard_name)
    StatusDashboard.notify_update(dashboard_name)

    assert_receive {:render, second_render_ms, _content}, 200
    assert second_render_ms > first_render_ms
    refute_receive {:render, _third_render_ms, _content}, 60
  end

  test "status dashboard keeps polling while disabled without rendering" do
    parent = self()

    state = %StatusDashboard{
      enabled: false,
      refresh_ms: 5,
      refresh_ms_override: 5,
      enabled_override: false,
      render_interval_ms: 16,
      render_interval_ms_override: 16,
      render_fun: fn _content -> send(parent, :rendered) end,
      token_samples: [],
      last_tps_second: nil,
      last_tps_value: nil,
      last_rendered_content: nil,
      last_rendered_at_ms: nil,
      pending_content: nil,
      flush_timer_ref: nil,
      last_snapshot_fingerprint: nil
    }

    assert {:noreply, next_state} = StatusDashboard.handle_info(:tick, state)
    refute next_state.enabled
    assert_receive :tick, 50
    refute_receive :rendered, 20
  end

  test "status dashboard emits structured snapshot render failure events" do
    dashboard_name = __MODULE__.ExplodingSnapshotDashboard
    orchestrator_pid = Process.whereis(SymphonyElixir.Orchestrator)

    on_exit(fn ->
      if is_nil(Process.whereis(SymphonyElixir.Orchestrator)) do
        case Process.whereis(SymphonyElixir.Supervisor) do
          pid when is_pid(pid) ->
            case Supervisor.restart_child(SymphonyElixir.Supervisor, SymphonyElixir.Orchestrator) do
              {:ok, _pid} -> :ok
              {:error, {:already_started, _pid}} -> :ok
              {:error, :running} -> :ok
            end

          _ ->
            :ok
        end
      end
    end)

    if is_pid(orchestrator_pid) do
      assert :ok = Supervisor.terminate_child(SymphonyElixir.Supervisor, SymphonyElixir.Orchestrator)
    end

    start_supervised!({MalformedSnapshotServer, name: SymphonyElixir.Orchestrator})

    {:ok, pid} =
      StatusDashboard.start_link(
        name: dashboard_name,
        enabled: true,
        refresh_ms: 60_000,
        render_interval_ms: 16,
        render_fun: fn _content -> :ok end
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    log =
      capture_log(fn ->
        send(pid, :refresh)
        Process.sleep(100)
      end)

    assert log =~ "dashboard_render_failed"
    assert log =~ "dashboard_render_failed"
    assert log =~ "BadMapError"
  end

  test "status dashboard emits structured terminal frame render failure events" do
    log =
      capture_log(fn ->
        Terminal.render_content(
          %StatusDashboard{
            render_fun: fn _content ->
              raise RuntimeError, "frame boom"
            end
          },
          "test frame",
          System.monotonic_time(:millisecond)
        )
      end)

    assert log =~ "dashboard_terminal_frame_render_failed"
    assert log =~ "frame boom"
  end

  test "status dashboard computes rolling 5-second token throughput" do
    assert Throughput.rolling_tps([], 10_000, 0) == 0.0

    assert Throughput.rolling_tps([{9_000, 20}], 10_000, 40) == 20.0

    # sample older than 5s is dropped from the window
    assert Throughput.rolling_tps([{4_900, 10}], 10_000, 90) == 0.0

    tps =
      Throughput.rolling_tps(
        [{9_500, 10}, {9_000, 40}, {8_000, 80}],
        10_000,
        95
      )

    assert tps == 7.5
  end

  test "status dashboard throttles tps updates to once per second" do
    {first_second, first_tps} =
      Throughput.throttled_tps(nil, nil, 10_000, [{9_000, 20}], 40)

    {same_second, same_tps} =
      Throughput.throttled_tps(first_second, first_tps, 10_500, [{9_000, 20}], 200)

    assert same_second == first_second
    assert same_tps == first_tps

    {next_second, next_tps} =
      Throughput.throttled_tps(same_second, same_tps, 11_000, [{10_500, 200}], 260)

    assert next_second == 11
    refute next_tps == same_tps
  end

  test "status dashboard renders 10-minute TPS graph snapshot for steady throughput" do
    now_ms = 600_000
    current_tokens = 6_000

    samples =
      for timestamp <- 575_000..0//-25_000 do
        {timestamp, div(timestamp, 100)}
      end

    assert Throughput.tps_graph(samples, now_ms, current_tokens) ==
             "████████████████████████"
  end

  test "status dashboard renders 10-minute TPS graph snapshot for ramping throughput" do
    now_ms = 600_000

    rates_per_bucket =
      1..24
      |> Enum.map(&(&1 * 2))

    {current_tokens, samples} = graph_samples_from_rates(rates_per_bucket)

    assert Throughput.tps_graph(samples, now_ms, current_tokens) ==
             "▁▂▂▂▃▃▃▃▄▄▄▅▅▅▆▆▆▆▇▇▇██▅"
  end

  test "status dashboard keeps historical TPS bars stable within the active bucket" do
    now_ms = 600_000
    current_tokens = 74_400
    next_current_tokens = current_tokens + 120
    samples = graph_samples_for_stability_test(now_ms)

    graph_at_now = Throughput.tps_graph(samples, now_ms, current_tokens)

    graph_next_second =
      Throughput.tps_graph(samples, now_ms + 1_000, next_current_tokens)

    historical_changes =
      graph_at_now
      |> String.graphemes()
      |> Enum.zip(String.graphemes(graph_next_second))
      |> Enum.take(23)
      |> Enum.count(fn {left, right} -> left != right end)

    assert historical_changes == 0
  end

  test "application configures a rotating file logger handler" do
    assert {:ok, handler_config} = :logger.get_handler_config(:symphony_disk_log)
    assert handler_config.module == :logger_disk_log_h

    disk_config = handler_config.config
    assert disk_config.type == :wrap
    assert is_list(disk_config.file)
    assert disk_config.max_no_bytes > 0
    assert disk_config.max_no_files > 0
  end

  test "status dashboard renders last codex message in EVENT column" do
    row =
      Presenter.format_running_summary(
        %{
          identifier: "MT-233",
          state: "running",
          session_id: "thread-1234567890",
          agent_process_pid: "4242",
          agent_total_tokens: 12,
          runtime_seconds: 15,
          last_agent_event: :notification,
          last_agent_message: %{
            event: :notification,
            message: %{
              "method" => "turn/completed",
              "params" => %{"turn" => %{"status" => "completed"}}
            }
          }
        },
        @dashboard_terminal_columns
      )

    plain = Regex.replace(~r/\e\[[0-9;]*m/, row, "")

    assert plain =~ "turn completed (completed)"
    assert (String.split(plain, "turn completed (completed)") |> length()) - 1 == 1
    refute plain =~ " notification "
  end

  test "status dashboard strips ANSI and control bytes from last codex message" do
    payload =
      "cmd: " <>
        <<27>> <>
        "[31mRED" <>
        <<27>> <>
        "[0m" <>
        <<0>> <>
        " after\nline"

    row =
      Presenter.format_running_summary(
        %{
          identifier: "MT-898",
          state: "running",
          session_id: "thread-1234567890",
          agent_process_pid: "4242",
          agent_total_tokens: 12,
          runtime_seconds: 15,
          last_agent_event: :notification,
          last_agent_message: payload
        },
        @dashboard_terminal_columns
      )

    plain = Regex.replace(~r/\e\[[0-9;]*m/, row, "")

    assert plain =~ "cmd: RED after line"
    refute plain =~ <<27>>
    refute plain =~ <<0>>
  end

  test "status dashboard expands running row to requested terminal width" do
    terminal_columns = 140

    row =
      Presenter.format_running_summary(
        %{
          identifier: "MT-598",
          state: "running",
          session_id: "thread-1234567890",
          agent_process_pid: "4242",
          agent_total_tokens: 123,
          runtime_seconds: 15,
          last_agent_event: :notification,
          last_agent_message: %{
            event: :notification,
            message: %{
              "method" => "turn/completed",
              "params" => %{"turn" => %{"status" => "completed"}}
            }
          }
        },
        terminal_columns
      )

    plain = Regex.replace(~r/\e\[[\d;]*m/, row, "")

    assert String.length(plain) == terminal_columns
    assert plain =~ "turn completed (completed)"
  end

  test "status dashboard presents full codex app-server event set" do
    event_cases = [
      {"turn/started", %{"params" => %{"turn" => %{"id" => "turn-1"}}}, "turn started"},
      {"turn/completed", %{"params" => %{"turn" => %{"status" => "completed"}}}, "turn completed"},
      {"turn/diff/updated", %{"params" => %{"diff" => "line1\nline2"}}, "turn diff updated"},
      {"turn/plan/updated", %{"params" => %{"plan" => [%{"step" => "a"}, %{"step" => "b"}]}}, "plan updated"},
      {"thread/tokenUsage/updated",
       %{
         "params" => %{
           "usage" => %{"input_tokens" => 8, "output_tokens" => 3, "total_tokens" => 11}
         }
       }, "thread token usage updated"},
      {"item/started",
       %{
         "params" => %{
           "item" => %{
             "id" => "item-1234567890abcdef",
             "type" => "commandExecution",
             "status" => "running"
           }
         }
       }, "item started: command execution"},
      {"item/completed", %{"params" => %{"item" => %{"type" => "fileChange", "status" => "completed"}}}, "item completed: file change"},
      {"item/agentMessage/delta", %{"params" => %{"delta" => "hello"}}, "agent message streaming"},
      {"item/plan/delta", %{"params" => %{"delta" => "step"}}, "plan streaming"},
      {"item/reasoning/summaryTextDelta", %{"params" => %{"summaryText" => "thinking"}}, "reasoning summary streaming"},
      {"item/reasoning/summaryPartAdded", %{"params" => %{"summaryText" => "section"}}, "reasoning summary section added"},
      {"item/reasoning/textDelta", %{"params" => %{"textDelta" => "reason"}}, "reasoning text streaming"},
      {"item/commandExecution/outputDelta", %{"params" => %{"outputDelta" => "ok"}}, "command output streaming"},
      {"item/fileChange/outputDelta", %{"params" => %{"outputDelta" => "changed"}}, "file change output streaming"},
      {"item/commandExecution/requestApproval", %{"params" => %{"parsedCmd" => "git status"}}, "command approval requested (git status)"},
      {"item/fileChange/requestApproval", %{"params" => %{"fileChangeCount" => 2}}, "file change approval requested (2 files)"},
      {"item/tool/call", %{"params" => %{"tool" => "linear_provider_diagnostics"}}, "dynamic tool call requested (linear_provider_diagnostics)"},
      {"item/tool/requestUserInput", %{"params" => %{"question" => "Continue?"}}, "tool requires user input: Continue?"}
    ]

    Enum.each(event_cases, fn {method, payload, expected_fragment} ->
      message = Map.put(payload, "method", method)

      presented =
        StatusDashboard.present_agent_message(%{event: :notification, message: message})

      assert presented =~ expected_fragment
    end)
  end

  test "status dashboard presents dynamic tool wrapper events" do
    completed = %{
      event: :tool_call_completed,
      message: %{
        payload: %{"method" => "item/tool/call", "params" => %{"name" => "linear_provider_diagnostics"}}
      }
    }

    failed = %{
      event: :tool_call_failed,
      message: %{
        payload: %{"method" => "item/tool/call", "params" => %{"tool" => "linear_provider_diagnostics"}}
      }
    }

    unsupported = %{
      event: :unsupported_tool_call,
      message: %{
        payload: %{"method" => "item/tool/call", "params" => %{"tool" => "unknown_tool"}}
      }
    }

    assert StatusDashboard.present_agent_message(completed) =~
             "dynamic tool call completed (linear_provider_diagnostics)"

    assert StatusDashboard.present_agent_message(failed) =~
             "dynamic tool call failed (linear_provider_diagnostics)"

    assert StatusDashboard.present_agent_message(unsupported) =~
             "unsupported dynamic tool call rejected (unknown_tool)"
  end

  test "status dashboard unwraps nested codex payload envelopes" do
    wrapped = %{
      event: :notification,
      message: %{
        payload: %{
          "method" => "turn/completed",
          "params" => %{
            "turn" => %{"status" => "completed"},
            "usage" => %{"input_tokens" => "10", "output_tokens" => 2, "total_tokens" => 12}
          }
        },
        raw: "{\"method\":\"turn/completed\"}"
      }
    }

    assert StatusDashboard.present_agent_message(wrapped) =~ "turn completed"
    assert StatusDashboard.present_agent_message(wrapped) =~ "in 10"
  end

  test "status dashboard uses shell command line as exec command status text" do
    message = %{
      event: :notification,
      message: %{
        "method" => "codex/event/exec_command_begin",
        "params" => %{"msg" => %{"command" => "git status --short"}}
      }
    }

    assert StatusDashboard.present_agent_message(message) == "git status --short"
  end

  test "status dashboard formats auto-approval updates from codex" do
    message = %{
      event: :approval_auto_approved,
      message: %{
        payload: %{
          "method" => "item/commandExecution/requestApproval",
          "params" => %{"parsedCmd" => "mix test"}
        },
        decision: "acceptForSession"
      }
    }

    presented = StatusDashboard.present_agent_message(message)
    assert presented =~ "command approval requested"
    assert presented =~ "auto-approved"
  end

  test "status dashboard formats auto-answered tool input updates from codex" do
    message = %{
      event: :tool_input_auto_answered,
      message: %{
        payload: %{
          "method" => "item/tool/requestUserInput",
          "params" => %{"question" => "Continue?"}
        },
        answer: "This is a non-interactive session. Operator input is unavailable."
      }
    }

    presented = StatusDashboard.present_agent_message(message)
    assert presented =~ "tool requires user input"
    assert presented =~ "auto-answered"
  end

  test "status dashboard enriches wrapper reasoning and message streaming events with payload context" do
    reasoning_message = %{
      event: :notification,
      message: %{
        "method" => "codex/event/agent_reasoning",
        "params" => %{
          "msg" => %{
            "payload" => %{"summaryText" => "compare retry paths for Linear polling"}
          }
        }
      }
    }

    message_delta = %{
      event: :notification,
      message: %{
        "method" => "codex/event/agent_message_delta",
        "params" => %{
          "msg" => %{
            "payload" => %{"delta" => "writing workpad reconciliation update"}
          }
        }
      }
    }

    default_reasoning = %{
      event: :notification,
      message: %{
        "method" => "codex/event/agent_reasoning",
        "params" => %{"msg" => %{"payload" => %{}}}
      }
    }

    assert StatusDashboard.present_agent_message(reasoning_message) =~
             "reasoning update: compare retry paths for Linear polling"

    assert StatusDashboard.present_agent_message(message_delta) =~
             "agent message streaming: writing workpad reconciliation update"

    assert StatusDashboard.present_agent_message(default_reasoning) == "reasoning update"
  end

  test "application stop renders offline status" do
    rendered =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = SymphonyElixir.Application.stop(:normal)
      end)

    assert rendered =~ "app_status=offline"
    refute rendered =~ "Timestamp:"
  end

  defp format_dashboard_snapshot(snapshot_data, tps, terminal_columns \\ @dashboard_terminal_columns) do
    Presenter.format_snapshot_content(
      snapshot_data,
      tps,
      terminal_columns,
      PresenterOptions.format(snapshot_data)
    )
  end

  defp wait_for_snapshot(pid, predicate, timeout_ms \\ 200) when is_function(predicate, 1) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_snapshot(pid, predicate, deadline_ms)
  end

  defp start_orchestrator(orchestrator_name) when is_atom(orchestrator_name) do
    Orchestrator.start_link(
      name: orchestrator_name,
      terminal_cleanup_opts: [
        fetch_terminal_issues: fn -> {:ok, []} end,
        cleanup_workspace: fn _identifier -> :ok end
      ]
    )
  end

  defp do_wait_for_snapshot(pid, predicate, deadline_ms) do
    snapshot = GenServer.call(pid, :snapshot)

    if predicate.(snapshot) do
      snapshot
    else
      if System.monotonic_time(:millisecond) >= deadline_ms do
        flunk("timed out waiting for orchestrator snapshot state: #{inspect(snapshot)}")
      else
        Process.sleep(5)
        do_wait_for_snapshot(pid, predicate, deadline_ms)
      end
    end
  end

  defp graph_samples_from_rates(rates_per_bucket) do
    bucket_ms = 25_000

    {timestamp, tokens, samples} =
      Enum.reduce(rates_per_bucket, {0, 0, []}, fn rate, {timestamp, tokens, acc} ->
        next_timestamp = timestamp + bucket_ms
        next_tokens = tokens + trunc(rate * bucket_ms / 1000)
        {next_timestamp, next_tokens, [{timestamp, tokens} | acc]}
      end)

    {tokens, [{timestamp, tokens} | samples]}
  end

  defp graph_samples_for_stability_test(now_ms) do
    rates_per_bucket = Enum.map(1..24, &(&1 * 5))
    bucket_ms = 25_000

    rate_for_timestamp = fn timestamp ->
      bucket_idx = min(div(max(timestamp, 0), bucket_ms), 23)
      Enum.at(rates_per_bucket, bucket_idx, 0)
    end

    0..(now_ms - 1_000)//1_000
    |> Enum.reduce({0, []}, fn timestamp, {tokens, acc} ->
      next_tokens = tokens + rate_for_timestamp.(timestamp)
      {next_tokens, [{timestamp, next_tokens} | acc]}
    end)
    |> elem(1)
  end

  defp wait_for_process_exit(pid, timeout_ms \\ 200) when is_pid(pid) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_process_exit(pid, deadline_ms)
  end

  defp do_wait_for_process_exit(pid, deadline_ms) when is_pid(pid) do
    cond do
      not Process.alive?(pid) ->
        true

      System.monotonic_time(:millisecond) >= deadline_ms ->
        false

      true ->
        Process.sleep(5)
        do_wait_for_process_exit(pid, deadline_ms)
    end
  end
end
