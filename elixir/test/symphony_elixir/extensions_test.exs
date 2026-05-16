defmodule SymphonyElixir.ExtensionsTest do
  use SymphonyElixir.TestSupport

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias SymphonyElixir.Tracker.Error, as: TrackerError
  alias SymphonyElixir.Tracker.Linear.Adapter
  alias SymphonyElixir.Tracker.Memory

  @endpoint SymphonyElixirWeb.Endpoint

  defmodule FakeLinearClient do
    def fetch_candidate_issues(_tracker) do
      send(self(), :fetch_candidate_issues_called)
      {:ok, [:candidate]}
    end

    def fetch_issues_by_states(states, _tracker) do
      send(self(), {:fetch_issues_by_states_called, states})
      {:ok, states}
    end

    def fetch_issue_states_by_ids(issue_ids, _tracker) do
      send(self(), {:fetch_issue_states_by_ids_called, issue_ids})
      {:ok, issue_ids}
    end

    def graphql(query, variables, _opts) do
      send(self(), {:graphql_called, query, variables})

      case Process.get({__MODULE__, :graphql_results}) do
        [result | rest] ->
          Process.put({__MODULE__, :graphql_results}, rest)
          result

        _ ->
          Process.get({__MODULE__, :graphql_result})
      end
    end

    def create_comment(issue_id, body, opts) do
      _tracker = Keyword.fetch!(opts, :tracker)

      case graphql("mutation { commentCreate(input: {issueId: $issueId, body: $body}) { success } }", %{issueId: issue_id, body: body}, []) do
        {:ok, %{"data" => %{"commentCreate" => %{"success" => true}}}} -> :ok
        {:error, reason} -> {:error, make_error(:create_comment, :unknown, reason)}
        _ -> {:error, make_error(:create_comment, :write_failed, :comment_create_failed)}
      end
    end

    def update_issue_state(issue_id, state_name, opts) do
      _tracker = Keyword.fetch!(opts, :tracker)

      case graphql("query { states }", %{issueId: issue_id, stateName: state_name}, []) do
        {:ok, %{"data" => %{"issue" => %{"team" => %{"states" => %{"nodes" => [%{"id" => state_id} | _]}}}}}} ->
          case graphql("mutation { issueUpdate }", %{issueId: issue_id, stateId: state_id}, []) do
            {:ok, %{"data" => %{"issueUpdate" => %{"success" => true}}}} -> :ok
            {:error, reason} -> {:error, make_error(:update_issue_state, :unknown, reason)}
            _ -> {:error, make_error(:update_issue_state, :write_failed, :issue_update_failed)}
          end

        {:error, reason} ->
          {:error, make_error(:update_issue_state, :unknown, reason)}

        _ ->
          {:error, make_error(:update_issue_state, :not_found, :state_not_found)}
      end
    end

    def healthcheck(opts) do
      _tracker = Keyword.fetch!(opts, :tracker)

      case graphql("query { viewer { id } }", %{}, []) do
        {:ok, %{"data" => %{"viewer" => %{"id" => id}}}} when is_binary(id) -> :ok
        {:error, reason} -> {:error, make_error(:healthcheck, :unknown, reason)}
        _ -> {:error, make_error(:healthcheck, :invalid_response, :healthcheck_failed)}
      end
    end

    defp make_error(operation, code, source_reason) do
      SymphonyElixir.Tracker.Error.new(%{
        provider: "linear",
        operation: operation,
        code: code,
        message: "Linear operation failed.",
        details: %{source_reason: source_reason}
      })
    end
  end

  defmodule TrackerAwareLinearClient do
    def fetch_candidate_issues(tracker) do
      send(self(), {:fetch_candidate_issues_called, tracker})
      {:ok, [:candidate]}
    end

    def fetch_issues_by_states(states, tracker) do
      send(self(), {:fetch_issues_by_states_called, states, tracker})
      {:ok, states}
    end

    def fetch_issue_states_by_ids(issue_ids, tracker) do
      send(self(), {:fetch_issue_states_by_ids_called, issue_ids, tracker})
      {:ok, issue_ids}
    end

    def graphql(query, variables, opts) do
      send(self(), {:graphql_called, query, variables, Keyword.get(opts, :tracker)})

      case Process.get({__MODULE__, :graphql_results}) do
        [result | rest] ->
          Process.put({__MODULE__, :graphql_results}, rest)
          result

        _ ->
          Process.get({__MODULE__, :graphql_result})
      end
    end

    def create_comment(issue_id, body, opts) do
      tracker = Keyword.fetch!(opts, :tracker)

      case graphql("mutation { commentCreate(input: {issueId: $issueId, body: $body}) { success } }", %{issueId: issue_id, body: body}, tracker: tracker) do
        {:ok, %{"data" => %{"commentCreate" => %{"success" => true}}}} -> :ok
        {:error, reason} -> {:error, reason}
        _ -> {:error, :comment_create_failed}
      end
    end

    def update_issue_state(issue_id, state_name, opts) do
      tracker = Keyword.fetch!(opts, :tracker)

      case graphql("query { states }", %{issueId: issue_id, stateName: state_name}, tracker: tracker) do
        {:ok, %{"data" => %{"issue" => %{"team" => %{"states" => %{"nodes" => [%{"id" => state_id} | _]}}}}}} ->
          case graphql("mutation { issueUpdate }", %{issueId: issue_id, stateId: state_id}, tracker: tracker) do
            {:ok, %{"data" => %{"issueUpdate" => %{"success" => true}}}} -> :ok
            {:error, reason} -> {:error, reason}
            _ -> {:error, :issue_update_failed}
          end

        {:error, reason} ->
          {:error, reason}

        _ ->
          {:error, :state_not_found}
      end
    end

    def healthcheck(opts) do
      tracker = Keyword.fetch!(opts, :tracker)

      case graphql("query { viewer { id } }", %{}, tracker: tracker) do
        {:ok, %{"data" => %{"viewer" => %{"id" => id}}}} when is_binary(id) -> :ok
        {:error, reason} -> {:error, reason}
        _ -> {:error, :healthcheck_failed}
      end
    end
  end

  defmodule SlowOrchestrator do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    def init(:ok), do: {:ok, :ok}

    def handle_call(:snapshot, _from, state) do
      Process.sleep(25)
      {:reply, %{}, state}
    end

    def handle_call(:request_refresh, _from, state) do
      {:reply, :unavailable, state}
    end
  end

  defmodule ExplodingOrchestrator do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    def init(:ok), do: {:ok, :ok}

    def handle_call(:snapshot, _from, state) do
      {:reply, %{running: nil, retrying: [], agent_totals: %{}, agent_rate_limits: nil}, state}
    end

    def handle_call(:request_refresh, _from, state) do
      {:reply, :unavailable, state}
    end
  end

  defmodule StaticOrchestrator do
    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    def init(opts), do: {:ok, opts}

    def handle_call(:snapshot, _from, state) do
      {:reply, Keyword.fetch!(state, :snapshot), state}
    end

    def handle_call(:request_refresh, _from, state) do
      {:reply, Keyword.get(state, :refresh, :unavailable), state}
    end
  end

  setup do
    linear_client_module = Application.get_env(:symphony_elixir, :linear_client_module)

    on_exit(fn ->
      if is_nil(linear_client_module) do
        Application.delete_env(:symphony_elixir, :linear_client_module)
      else
        Application.put_env(:symphony_elixir, :linear_client_module, linear_client_module)
      end
    end)

    :ok
  end

  setup do
    endpoint_config = Application.get_env(:symphony_elixir, SymphonyElixirWeb.Endpoint, [])

    on_exit(fn ->
      Application.put_env(:symphony_elixir, SymphonyElixirWeb.Endpoint, endpoint_config)
    end)

    :ok
  end

  test "workflow store reloads changes, keeps last good workflow, and uses the default when stopped" do
    ensure_workflow_store_running()
    assert {:ok, %{prompt: "You are an agent for this repository."}} = Workflow.current()

    write_workflow_file!(Workflow.workflow_file_path(), prompt: "Second prompt")
    send(WorkflowStore, :poll)

    assert_eventually(fn ->
      match?({:ok, %{prompt: "Second prompt"}}, Workflow.current())
    end)

    File.write!(Workflow.workflow_file_path(), "---\ntracker: [\n---\nBroken prompt\n")
    assert {:error, _reason} = WorkflowStore.force_reload()
    assert {:ok, %{prompt: "Second prompt"}} = Workflow.current()

    third_workflow = Path.join(Path.dirname(Workflow.workflow_file_path()), "THIRD_WORKFLOW.md")
    write_workflow_file!(third_workflow, prompt: "Third prompt")
    Workflow.set_workflow_file_path(third_workflow)
    assert {:ok, %{prompt: "Third prompt"}} = Workflow.current()

    assert :ok = terminate_supervised_child(WorkflowStore)
    assert {:ok, %{prompt: "Third prompt"}} = WorkflowStore.current()
    assert :ok = WorkflowStore.force_reload()
    assert :ok = restart_supervised_child(WorkflowStore)
  end

  test "workflow store init stops on missing workflow file" do
    missing_path = Path.join(Path.dirname(Workflow.workflow_file_path()), "MISSING_WORKFLOW.md")
    Workflow.set_workflow_file_path(missing_path)

    assert {:stop, {:missing_workflow_file, ^missing_path, :enoent}} = WorkflowStore.init([])
  end

  test "workflow store start_link and poll callback cover missing-file error paths" do
    ensure_workflow_store_running()
    existing_path = Workflow.workflow_file_path()
    manual_path = Path.join(Path.dirname(existing_path), "MANUAL_WORKFLOW.md")
    missing_path = Path.join(Path.dirname(existing_path), "MANUAL_MISSING_WORKFLOW.md")

    assert :ok = terminate_supervised_child(WorkflowStore)

    Workflow.set_workflow_file_path(missing_path)

    assert {:error, {:missing_workflow_file, ^missing_path, :enoent}} =
             WorkflowStore.force_reload()

    write_workflow_file!(manual_path, prompt: "Manual workflow prompt")
    Workflow.set_workflow_file_path(manual_path)

    assert {:ok, manual_pid} = WorkflowStore.start_link()
    assert Process.alive?(manual_pid)

    state = :sys.get_state(manual_pid)
    File.write!(manual_path, "---\ntracker: [\n---\nBroken prompt\n")
    assert {:noreply, returned_state} = WorkflowStore.handle_info(:poll, state)
    assert returned_state.workflow.prompt == "Manual workflow prompt"
    refute returned_state.stamp == nil
    assert_receive :poll, 1_100

    Workflow.set_workflow_file_path(missing_path)
    assert {:noreply, path_error_state} = WorkflowStore.handle_info(:poll, returned_state)
    assert path_error_state.workflow.prompt == "Manual workflow prompt"
    assert_receive :poll, 1_100

    Workflow.set_workflow_file_path(manual_path)
    File.rm!(manual_path)
    assert {:noreply, removed_state} = WorkflowStore.handle_info(:poll, path_error_state)
    assert removed_state.workflow.prompt == "Manual workflow prompt"
    assert_receive :poll, 1_100

    Process.exit(manual_pid, :normal)
    assert :ok = restart_supervised_child(WorkflowStore)

    Workflow.set_workflow_file_path(existing_path)
    WorkflowStore.force_reload()
  end

  test "workflow store emits structured lifecycle events for load and reload failures" do
    ensure_workflow_store_running()
    existing_path = Workflow.workflow_file_path()
    manual_path = Path.join(Path.dirname(existing_path), "STRUCTURED_WORKFLOW.md")

    assert :ok = terminate_supervised_child(WorkflowStore)

    write_workflow_file!(manual_path, prompt: "Structured workflow prompt")
    Workflow.set_workflow_file_path(manual_path)

    start_log =
      capture_log(fn ->
        assert {:ok, manual_pid} = WorkflowStore.start_link()
        send(self(), {:manual_workflow_state, :sys.get_state(manual_pid)})
        Process.exit(manual_pid, :normal)
      end)

    assert start_log =~ "workflow_loaded"
    assert_receive {:manual_workflow_state, state}

    File.write!(manual_path, "---\ntracker: [\n---\nBroken prompt\n")

    reload_log =
      capture_log(fn ->
        assert {:noreply, _returned_state} = WorkflowStore.handle_info(:poll, state)
      end)

    assert reload_log =~ "workflow_reload_failed"

    assert :ok = restart_supervised_child(WorkflowStore)

    Workflow.set_workflow_file_path(existing_path)
    WorkflowStore.force_reload()
  end

  test "workflow store emits a structured event when observability reconfigure is skipped" do
    ensure_workflow_store_running()

    log =
      capture_log(fn ->
        write_workflow_file!(Workflow.workflow_file_path(),
          observability_refresh_ms: 0,
          observability_render_interval_ms: 0,
          observability_log_format: "invalid"
        )

        assert :ok = WorkflowStore.force_reload()
      end)

    assert log =~ "workflow_observability_config_invalid"
    assert log =~ "observability_config_reconfigure_skipped"
    assert log =~ "workflow_path="
    assert log =~ "workflow_loaded"
  end

  test "tracker delegates to memory and linear adapters" do
    issue = %Issue{id: "issue-1", identifier: "MT-1", state: "In Progress"}
    Application.put_env(:symphony_elixir, :memory_tracker_issues, [issue, %{id: "ignored"}])
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
    tracker = Config.settings!().tracker

    assert tracker.kind == "memory"
    assert SymphonyElixir.Tracker.adapter() == Memory
    assert {:ok, [^issue]} = SymphonyElixir.Tracker.fetch_candidate_issues()
    assert {:ok, [^issue]} = SymphonyElixir.Tracker.fetch_issues_by_states([" in progress ", 42])
    assert {:ok, [^issue]} = SymphonyElixir.Tracker.fetch_issue_states_by_ids(["issue-1"])
    assert :ok = SymphonyElixir.Tracker.create_comment("issue-1", "comment")
    assert :ok = SymphonyElixir.Tracker.update_issue_state("issue-1", "Done")
    assert_receive {:memory_tracker_comment, "issue-1", "comment"}
    assert_receive {:memory_tracker_state_update, "issue-1", "Done"}

    Application.delete_env(:symphony_elixir, :memory_tracker_recipient)
    assert :ok = Memory.create_comment(tracker, "issue-1", "quiet")
    assert :ok = Memory.update_issue_state(tracker, "issue-1", "Quiet")

    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "linear")
    assert SymphonyElixir.Tracker.adapter() == Adapter
  end

  test "terminal issue fetch respects configured candidate issue ids" do
    done = %Issue{id: "done-1", identifier: "MT-1", state: "Done"}
    other_done = %Issue{id: "done-2", identifier: "MT-2", state: "Done"}
    active = %Issue{id: "active-1", identifier: "MT-3", state: "In Progress"}

    Application.put_env(:symphony_elixir, :memory_tracker_issues, [done, other_done, active])

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      tracker_terminal_states: ["Done"],
      tracker_provider: %{"candidate_issue_ids" => ["done-1", "active-1", "missing"]}
    )

    assert {:ok, [^done]} = SymphonyElixir.Tracker.fetch_terminal_issues()
  end

  test "linear adapter delegates reads and validates mutation responses" do
    Application.put_env(:symphony_elixir, :linear_client_module, FakeLinearClient)
    tracker = explicit_linear_tracker()

    assert {:ok, [:candidate]} = Adapter.fetch_candidate_issues(tracker)
    assert_receive :fetch_candidate_issues_called

    assert {:ok, ["Todo"]} = Adapter.fetch_issues_by_states(tracker, ["Todo"])
    assert_receive {:fetch_issues_by_states_called, ["Todo"]}

    assert {:ok, ["issue-1"]} = Adapter.fetch_issue_states_by_ids(tracker, ["issue-1"])
    assert_receive {:fetch_issue_states_by_ids_called, ["issue-1"]}

    Process.put(
      {FakeLinearClient, :graphql_result},
      {:ok, %{"data" => %{"commentCreate" => %{"success" => true}}}}
    )

    assert :ok = Adapter.create_comment(tracker, "issue-1", "hello")
    assert_receive {:graphql_called, create_comment_query, %{body: "hello", issueId: "issue-1"}}
    assert create_comment_query =~ "commentCreate"

    Process.put(
      {FakeLinearClient, :graphql_result},
      {:ok, %{"data" => %{"commentCreate" => %{"success" => false}}}}
    )

    assert_tracker_error(
      Adapter.create_comment(tracker, "issue-1", "broken"),
      :create_comment,
      :write_failed,
      :comment_create_failed
    )

    Process.put({FakeLinearClient, :graphql_result}, {:error, :boom})

    assert_tracker_error(
      Adapter.create_comment(tracker, "issue-1", "boom"),
      :create_comment,
      :unknown,
      :boom
    )

    Process.put({FakeLinearClient, :graphql_result}, {:ok, %{"data" => %{}}})

    assert_tracker_error(
      Adapter.create_comment(tracker, "issue-1", "weird"),
      :create_comment,
      :write_failed,
      :comment_create_failed
    )

    Process.put({FakeLinearClient, :graphql_result}, :unexpected)

    assert_tracker_error(
      Adapter.create_comment(tracker, "issue-1", "odd"),
      :create_comment,
      :write_failed,
      :comment_create_failed
    )

    Process.put(
      {FakeLinearClient, :graphql_results},
      [
        {:ok,
         %{
           "data" => %{
             "issue" => %{"team" => %{"states" => %{"nodes" => [%{"id" => "state-1"}]}}}
           }
         }},
        {:ok, %{"data" => %{"issueUpdate" => %{"success" => true}}}}
      ]
    )

    assert :ok = Adapter.update_issue_state(tracker, "issue-1", "Done")
    assert_receive {:graphql_called, state_lookup_query, %{issueId: "issue-1", stateName: "Done"}}
    assert state_lookup_query =~ "states"

    assert_receive {:graphql_called, update_issue_query, %{issueId: "issue-1", stateId: "state-1"}}

    assert update_issue_query =~ "issueUpdate"

    Process.put(
      {FakeLinearClient, :graphql_results},
      [
        {:ok,
         %{
           "data" => %{
             "issue" => %{"team" => %{"states" => %{"nodes" => [%{"id" => "state-1"}]}}}
           }
         }},
        {:ok, %{"data" => %{"issueUpdate" => %{"success" => false}}}}
      ]
    )

    assert_tracker_error(
      Adapter.update_issue_state(tracker, "issue-1", "Broken"),
      :update_issue_state,
      :write_failed,
      :issue_update_failed
    )

    Process.put({FakeLinearClient, :graphql_results}, [{:error, :boom}])

    assert_tracker_error(
      Adapter.update_issue_state(tracker, "issue-1", "Boom"),
      :update_issue_state,
      :unknown,
      :boom
    )

    Process.put({FakeLinearClient, :graphql_results}, [{:ok, %{"data" => %{}}}])

    assert_tracker_error(
      Adapter.update_issue_state(tracker, "issue-1", "Missing"),
      :update_issue_state,
      :not_found,
      :state_not_found
    )

    Process.put(
      {FakeLinearClient, :graphql_results},
      [
        {:ok,
         %{
           "data" => %{
             "issue" => %{"team" => %{"states" => %{"nodes" => [%{"id" => "state-1"}]}}}
           }
         }},
        {:ok, %{"data" => %{}}}
      ]
    )

    assert_tracker_error(
      Adapter.update_issue_state(tracker, "issue-1", "Weird"),
      :update_issue_state,
      :write_failed,
      :issue_update_failed
    )

    Process.put(
      {FakeLinearClient, :graphql_results},
      [
        {:ok,
         %{
           "data" => %{
             "issue" => %{"team" => %{"states" => %{"nodes" => [%{"id" => "state-1"}]}}}
           }
         }},
        :unexpected
      ]
    )

    assert_tracker_error(
      Adapter.update_issue_state(tracker, "issue-1", "Odd"),
      :update_issue_state,
      :write_failed,
      :issue_update_failed
    )
  end

  test "tracker supports explicit tracker config with tracker-aware linear client" do
    Application.put_env(:symphony_elixir, :linear_client_module, TrackerAwareLinearClient)
    tracker = explicit_linear_tracker()

    assert SymphonyElixir.Tracker.adapter(tracker) == Adapter

    assert SymphonyElixir.Tracker.dynamic_tools(tracker) |> Enum.map(&Map.fetch!(&1, "name")) ==
             [
               "linear_issue_snapshot",
               "linear_move_issue",
               "linear_upsert_workpad",
               "linear_attach_change_proposal",
               "linear_upsert_comment",
               "linear_prepare_file_upload",
               "linear_provider_diagnostics"
             ]

    assert {:ok, [:candidate]} = SymphonyElixir.Tracker.fetch_candidate_issues(tracker)
    assert_receive {:fetch_candidate_issues_called, ^tracker}

    assert {:ok, ["Todo"]} = SymphonyElixir.Tracker.fetch_issues_by_states(tracker, ["Todo"])
    assert_receive {:fetch_issues_by_states_called, ["Todo"], ^tracker}

    assert {:ok, ["issue-1"]} = SymphonyElixir.Tracker.fetch_issue_states_by_ids(tracker, ["issue-1"])
    assert_receive {:fetch_issue_states_by_ids_called, ["issue-1"], ^tracker}

    Process.put(
      {TrackerAwareLinearClient, :graphql_result},
      {:ok, %{"data" => %{"commentCreate" => %{"success" => true}}}}
    )

    assert :ok = SymphonyElixir.Tracker.create_comment(tracker, "issue-1", "hello")

    assert_receive {:graphql_called, create_comment_query, %{body: "hello", issueId: "issue-1"}, ^tracker}

    assert create_comment_query =~ "commentCreate"

    Process.put(
      {TrackerAwareLinearClient, :graphql_results},
      [
        {:ok,
         %{
           "data" => %{
             "issue" => %{"team" => %{"states" => %{"nodes" => [%{"id" => "state-1"}]}}}
           }
         }},
        {:ok, %{"data" => %{"issueUpdate" => %{"success" => true}}}}
      ]
    )

    assert :ok = SymphonyElixir.Tracker.update_issue_state(tracker, "issue-1", "Done")

    assert_receive {:graphql_called, state_lookup_query, %{issueId: "issue-1", stateName: "Done"}, ^tracker}
    assert state_lookup_query =~ "states"

    assert_receive {:graphql_called, update_issue_query, %{issueId: "issue-1", stateId: "state-1"}, ^tracker}
    assert update_issue_query =~ "issueUpdate"
  end

  test "linear adapter explicit tracker path uses the configured client contract" do
    Application.put_env(:symphony_elixir, :linear_client_module, FakeLinearClient)
    tracker = explicit_linear_tracker()

    assert {:ok, [:candidate]} = Adapter.fetch_candidate_issues(tracker)
    assert_receive :fetch_candidate_issues_called

    assert {:ok, ["Todo"]} = Adapter.fetch_issues_by_states(tracker, ["Todo"])
    assert_receive {:fetch_issues_by_states_called, ["Todo"]}

    assert {:ok, ["issue-1"]} = Adapter.fetch_issue_states_by_ids(tracker, ["issue-1"])
    assert_receive {:fetch_issue_states_by_ids_called, ["issue-1"]}
  end

  test "phoenix observability api preserves state, issue, and refresh responses" do
    snapshot = static_snapshot()
    orchestrator_name = __MODULE__.ObservabilityApiOrchestrator

    SymphonyElixir.Observability.EventStore.reset()

    capture_log(fn ->
      SymphonyElixir.Observability.Logger.emit(:info, :workspace_prepare_started, %{
        component: "workspace",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        workspace_path: Path.join(Config.settings!().workspace.root, "MT-HTTP")
      })

      SymphonyElixir.Observability.Logger.emit(:info, :codex_session_started, %{
        component: "codex.app_server",
        run_id: "run-http",
        thread_id: "thread-http"
      })

      SymphonyElixir.Observability.Logger.emit(:info, :codex_turn_started, %{
        component: "codex.app_server",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        thread_id: "thread-http",
        turn_id: "turn-1"
      })
    end)

    {:ok, _pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: snapshot,
        refresh: %{
          queued: true,
          coalesced: false,
          requested_at: DateTime.utc_now(),
          operations: ["poll", "reconcile"]
        }
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    conn = get(build_conn(), "/api/v1/state")
    state_payload = json_response(conn, 200)
    state_recent_events = state_payload["recent_events"]

    assert state_payload == %{
             "generated_at" => state_payload["generated_at"],
             "counts" => %{"running" => 1, "retrying" => 1},
             "running" => [
               %{
                 "issue_id" => "issue-http",
                 "issue_identifier" => "MT-HTTP",
                 "run_id" => "run-http",
                 "state" => "In Progress",
                 "worker_host" => nil,
                 "workspace_path" => nil,
                 "session_id" => "thread-http",
                 "turn_count" => 7,
                 "turn" => %{
                   "turn_number" => 7,
                   "max_turns" => Config.settings!().agent.execution.max_turns,
                   "status" => "running",
                   "started_at" => nil,
                   "updated_at" => nil,
                   "duration_ms" => nil,
                   "error_code" => nil
                 },
                 "provider" => %{
                   "kind" => "codex",
                   "capabilities" => [
                     "agent.turn.run",
                     "agent.session.stateful",
                     "agent.events.streaming",
                     "agent.usage.metrics",
                     "agent.tools.dynamic",
                     "agent.runtime.remote_worker",
                     "agent.credentials.managed"
                   ],
                   "session_id" => "thread-http",
                   "thread_id" => nil,
                   "turn_id" => nil,
                   "stateful" => true
                 },
                 "worker" => %{"host" => nil, "workspace_path" => nil, "status" => "running"},
                 "agent" => %{
                   "provider_kind" => "codex",
                   "process_pid" => nil,
                   "last_event" => "notification",
                   "last_message" => "rendered",
                   "last_event_at" => nil,
                   "tokens" => %{"input_tokens" => 4, "output_tokens" => 8, "total_tokens" => 12}
                 },
                 "last_event" => "notification",
                 "last_message" => "rendered",
                 "started_at" => state_payload["running"] |> List.first() |> Map.fetch!("started_at"),
                 "last_event_at" => nil,
                 "tokens" => %{"input_tokens" => 4, "output_tokens" => 8, "total_tokens" => 12}
               }
             ],
             "retrying" => [
               %{
                 "issue_id" => "issue-retry",
                 "issue_identifier" => "MT-RETRY",
                 "attempt" => 2,
                 "run_id" => nil,
                 "due_at" => state_payload["retrying"] |> List.first() |> Map.fetch!("due_at"),
                 "error" => "boom",
                 "worker_host" => nil,
                 "workspace_path" => nil,
                 "agent" => %{
                   "run_id" => nil,
                   "status" => "retry_scheduled",
                   "attempt" => 2,
                   "started_at" => nil,
                   "updated_at" => nil,
                   "duration_ms" => nil,
                   "terminal_reason" => "boom"
                 },
                 "provider" => %{
                   "kind" => nil,
                   "capabilities" => [],
                   "session_id" => nil,
                   "thread_id" => nil,
                   "turn_id" => nil,
                   "stateful" => false
                 },
                 "worker" => %{"host" => nil, "workspace_path" => nil, "status" => "retry_scheduled"}
               }
             ],
             "agent_totals" => %{
               "input_tokens" => 4,
               "output_tokens" => 8,
               "total_tokens" => 12,
               "seconds_running" => 42.5
             },
             "agent_rate_limits" => %{"primary" => %{"remaining" => 11}},
             "dynamic_tool_metrics" => SymphonyElixir.Observability.EventStore.Query.empty_dynamic_tool_usage_metrics(),
             "recent_events" => state_recent_events
           }

    state_run_events = Enum.filter(state_recent_events, &(Map.get(&1, "run_id") == "run-http"))

    assert Enum.map(state_run_events, & &1["event"]) == [
             "codex_turn_started",
             "codex_session_started",
             "workspace_prepare_started"
           ]

    conn = get(build_conn(), "/api/v1/MT-HTTP")
    issue_payload = json_response(conn, 200)
    workspace_path = Path.join(Config.settings!().workspace.root, "MT-HTTP")

    assert %{
             "issue_identifier" => "MT-HTTP",
             "issue_id" => "issue-http",
             "status" => "running",
             "workspace" => %{"path" => ^workspace_path, "host" => nil},
             "attempts" => %{"restart_count" => 0, "current_retry_attempt" => 0},
             "running" => %{
               "worker_host" => nil,
               "workspace_path" => nil,
               "run_id" => "run-http",
               "session_id" => "thread-http",
               "turn_count" => 7,
               "state" => "In Progress",
               "started_at" => _started_at,
               "agent" => %{
                 "provider_kind" => "codex",
                 "process_pid" => nil,
                 "last_event" => "notification",
                 "last_message" => "rendered",
                 "last_event_at" => nil,
                 "tokens" => %{"input_tokens" => 4, "output_tokens" => 8, "total_tokens" => 12}
               },
               "last_event" => "notification",
               "last_message" => "rendered",
               "last_event_at" => nil,
               "tokens" => %{"input_tokens" => 4, "output_tokens" => 8, "total_tokens" => 12}
             },
             "retry" => nil,
             "logs" => %{"agent_session_logs" => agent_session_logs},
             "recent_events" => recent_events,
             "last_error" => nil,
             "tracked" => %{}
           } = issue_payload

    assert issue_payload["agent"]["status"] == "running"
    assert issue_payload["agent"]["run_id"] == "run-http"
    assert issue_payload["turn"]["turn_number"] == 7
    assert issue_payload["provider"]["kind"] == "codex"
    assert issue_payload["provider"]["stateful"] == true
    assert issue_payload["worker"] == %{"host" => nil, "workspace_path" => nil, "status" => "running"}

    assert Enum.map(agent_session_logs, & &1["event"]) == [
             "codex_session_started",
             "codex_turn_started"
           ]

    assert Enum.map(recent_events, & &1["event"]) == [
             "codex_turn_started",
             "codex_session_started",
             "workspace_prepare_started"
           ]

    assert %{
             "component" => "codex.app_server",
             "correlation_id" => "run-http",
             "event" => "codex_session_started",
             "level" => "info",
             "message" => session_started_message,
             "run_id" => "run-http",
             "service" => "symphony_elixir",
             "thread_id" => "thread-http",
             "timestamp" => _timestamp
           } = List.first(agent_session_logs)

    assert session_started_message =~ "correlation_id=run-http"
    assert session_started_message =~ "run_id=run-http"

    assert %{
             "component" => "codex.app_server",
             "correlation_id" => "run-http",
             "event" => "codex_turn_started",
             "issue_id" => "issue-http",
             "issue_identifier" => "MT-HTTP",
             "level" => "info",
             "message" => turn_started_message,
             "run_id" => "run-http",
             "service" => "symphony_elixir",
             "session_id" => "thread-http",
             "thread_id" => "thread-http",
             "timestamp" => _timestamp,
             "turn_id" => "turn-1"
           } = List.last(agent_session_logs)

    assert turn_started_message =~ "correlation_id=run-http"
    assert turn_started_message =~ "turn_id=turn-1"

    assert %{
             "component" => "workspace",
             "correlation_id" => "run-http",
             "event" => "workspace_prepare_started",
             "issue_id" => "issue-http",
             "issue_identifier" => "MT-HTTP",
             "level" => "info",
             "message" => workspace_message,
             "run_id" => "run-http",
             "service" => "symphony_elixir",
             "timestamp" => _timestamp,
             "workspace_path" => ^workspace_path
           } = List.last(recent_events)

    assert workspace_message =~ "correlation_id=run-http"
    assert workspace_message =~ workspace_path

    conn = get(build_conn(), "/api/v1/MT-RETRY")

    assert %{"status" => "retrying", "retry" => %{"attempt" => 2, "error" => "boom"}} =
             json_response(conn, 200)

    conn = get(build_conn(), "/api/v1/MT-MISSING")

    assert json_response(conn, 404) == %{
             "error" => %{"code" => "issue_not_found", "message" => "Issue not found"}
           }

    conn = post(build_conn(), "/api/v1/refresh", %{})

    assert %{"queued" => true, "coalesced" => false, "operations" => ["poll", "reconcile"]} =
             json_response(conn, 202)
  end

  test "phoenix observability api exposes scoped dynamic tool metrics and operator alerts" do
    snapshot = static_snapshot()
    orchestrator_name = __MODULE__.DynamicToolMetricsApiOrchestrator

    SymphonyElixir.Observability.EventStore.reset()

    capture_log(fn ->
      SymphonyElixir.Observability.Logger.emit(:info, :tool_call_succeeded, %{
        component: "agent.dynamic_tool_bridge",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        tool_name: "repo_read_change_proposal_discussion",
        dynamic_tool_usage_kind: "typed",
        dynamic_tool_workflow_capability: "repo.read_change_proposal_discussion"
      })

      SymphonyElixir.Observability.Logger.emit(:info, :tool_call_succeeded, %{
        component: "agent.dynamic_tool_bridge",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        tool_name: "repo_change_proposal_snapshot",
        dynamic_tool_usage_kind: "typed",
        dynamic_tool_workflow_capability: "repo.change_proposal_snapshot",
        dynamic_tool_provider_capability_unavailable: [
          %{
            "workflowCapability" => "repo.submit_change_proposal_review",
            "reason" => "provider_capability_not_available",
            "description" => "formal PR reviews"
          }
        ]
      })

      SymphonyElixir.Observability.Logger.emit(:warning, :tool_call_rejected, %{
        component: "agent.dynamic_tool_bridge",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        tool_name: "tapd_api",
        dynamic_tool_usage_kind: "raw",
        dynamic_tool_failure_reason: "unsupported_tool"
      })

      SymphonyElixir.Observability.Logger.emit(:warning, :tool_call_failed, %{
        component: "agent.dynamic_tool_bridge",
        issue_id: "issue-other",
        issue_identifier: "MT-OTHER",
        run_id: "run-other",
        session_id: "thread-other",
        tool_name: "legacy_tracker_api",
        dynamic_tool_usage_kind: "fallback",
        dynamic_tool_failure_reason: "operator_migration"
      })
    end)

    {:ok, _pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: snapshot,
        refresh: %{queued: false, coalesced: false, requested_at: DateTime.utc_now(), operations: []}
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    state_metrics =
      build_conn()
      |> get("/api/v1/state")
      |> json_response(200)
      |> Map.fetch!("dynamic_tool_metrics")

    assert state_metrics["total_calls"] == 4
    assert state_metrics["typed_tool_hits"] == 2
    assert state_metrics["raw_tool_attempts"] == 1
    assert state_metrics["fallback_count"] == 1
    assert state_metrics["unsupported_tool_count"] == 1
    assert state_metrics["provider_capability_unavailable_count"] == 1
    assert state_metrics["operator_status"] == "critical"

    issue_metrics =
      build_conn()
      |> get("/api/v1/MT-HTTP")
      |> json_response(200)
      |> Map.fetch!("dynamic_tool_metrics")

    assert issue_metrics["total_calls"] == 3
    assert issue_metrics["typed_tool_hits"] == 2
    assert issue_metrics["raw_tool_attempts"] == 1
    assert issue_metrics["fallback_count"] == 0
    assert issue_metrics["unsupported_tool_count"] == 1
    assert issue_metrics["operator_status"] == "critical"

    assert issue_metrics["provider_capability_unavailable"] == %{
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

    assert Enum.map(issue_metrics["operator_alerts"], & &1["code"]) == [
             "raw_tool_attempts",
             "unsupported_tool_calls",
             "provider_capability_unavailable_known"
           ]
  end

  test "phoenix observability api prefers provider-neutral agent projection" do
    orchestrator_name = __MODULE__.AgentProjectionObservabilityApiOrchestrator

    snapshot =
      static_snapshot()
      |> Map.put(:agent_totals, %{input_tokens: 14, output_tokens: 16, total_tokens: 30, seconds_running: 10.5})
      |> Map.put(:agent_rate_limits, %{"generic" => %{"remaining" => 5}})
      |> Map.update!(:running, fn [entry] ->
        [
          Map.merge(entry, %{
            agent_provider_kind: "opencode",
            agent_process_pid: "agent-321",
            last_agent_event: :agent_message,
            last_agent_message: "generic rendered",
            last_agent_timestamp: DateTime.utc_now(),
            agent_input_tokens: 14,
            agent_output_tokens: 16,
            agent_total_tokens: 30
          })
        ]
      end)

    {:ok, _pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: snapshot,
        refresh: :unavailable
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    state_payload = json_response(get(build_conn(), "/api/v1/state"), 200)
    [running_entry] = state_payload["running"]

    assert state_payload["agent_totals"]["total_tokens"] == 30
    assert state_payload["agent_rate_limits"] == %{"generic" => %{"remaining" => 5}}
    assert running_entry["agent"]["provider_kind"] == "opencode"
    assert running_entry["agent"]["process_pid"] == "agent-321"
    assert running_entry["last_event"] == "agent_message"
    assert running_entry["last_message"] == "generic rendered"
    assert running_entry["tokens"] == %{"input_tokens" => 14, "output_tokens" => 16, "total_tokens" => 30}

    issue_payload = json_response(get(build_conn(), "/api/v1/MT-HTTP"), 200)

    assert issue_payload["running"]["agent"]["provider_kind"] == "opencode"
    assert issue_payload["running"]["last_message"] == "generic rendered"
    assert issue_payload["running"]["tokens"]["total_tokens"] == 30
  end

  test "phoenix observability api preserves 405, 404, and unavailable behavior" do
    unavailable_orchestrator = __MODULE__.UnavailableOrchestrator
    start_test_endpoint(orchestrator: unavailable_orchestrator, snapshot_timeout_ms: 5)

    assert json_response(post(build_conn(), "/api/v1/state", %{}), 405) ==
             %{"error" => %{"code" => "method_not_allowed", "message" => "Method not allowed"}}

    assert json_response(get(build_conn(), "/api/v1/refresh"), 405) ==
             %{"error" => %{"code" => "method_not_allowed", "message" => "Method not allowed"}}

    assert json_response(post(build_conn(), "/", %{}), 405) ==
             %{"error" => %{"code" => "method_not_allowed", "message" => "Method not allowed"}}

    assert json_response(post(build_conn(), "/api/v1/MT-1", %{}), 405) ==
             %{"error" => %{"code" => "method_not_allowed", "message" => "Method not allowed"}}

    assert json_response(get(build_conn(), "/unknown"), 404) ==
             %{"error" => %{"code" => "not_found", "message" => "Route not found"}}

    state_payload = json_response(get(build_conn(), "/api/v1/state"), 200)

    assert state_payload ==
             %{
               "generated_at" => state_payload["generated_at"],
               "error" => %{"code" => "snapshot_unavailable", "message" => "Snapshot unavailable"}
             }

    assert json_response(post(build_conn(), "/api/v1/refresh", %{}), 503) ==
             %{
               "error" => %{
                 "code" => "orchestrator_unavailable",
                 "message" => "Orchestrator is unavailable"
               }
             }
  end

  test "phoenix observability api preserves snapshot timeout behavior" do
    timeout_orchestrator = __MODULE__.TimeoutOrchestrator
    {:ok, _pid} = SlowOrchestrator.start_link(name: timeout_orchestrator)
    start_test_endpoint(orchestrator: timeout_orchestrator, snapshot_timeout_ms: 1)

    timeout_payload = json_response(get(build_conn(), "/api/v1/state"), 200)

    assert timeout_payload ==
             %{
               "generated_at" => timeout_payload["generated_at"],
               "error" => %{"code" => "snapshot_timeout", "message" => "Snapshot timed out"}
             }
  end

  test "phoenix observability api emits request outcome events" do
    snapshot = static_snapshot()
    orchestrator_name = __MODULE__.ObservabilityApiEventsOrchestrator

    {:ok, _pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: snapshot,
        refresh: %{
          queued: true,
          coalesced: false,
          requested_at: DateTime.utc_now(),
          operations: ["poll"]
        }
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    log =
      capture_log(fn ->
        assert json_response(get(build_conn(), "/api/v1/state"), 200)["counts"] ==
                 %{"running" => 1, "retrying" => 1}

        assert json_response(get(build_conn(), "/api/v1/MT-HTTP"), 200)["issue_identifier"] ==
                 "MT-HTTP"

        assert json_response(post(build_conn(), "/api/v1/refresh", %{}), 202)["queued"] == true

        assert json_response(get(build_conn(), "/api/v1/MT-MISSING"), 404)["error"]["code"] ==
                 "issue_not_found"

        assert json_response(post(build_conn(), "/api/v1/state", %{}), 405)["error"]["code"] ==
                 "method_not_allowed"
      end)

    assert log =~ "observability_api_request_completed method=GET path=/api/v1/state status=200"
    assert log =~ "observability_api_request_completed method=GET path=/api/v1/MT-HTTP status=200"
    assert log =~ "issue_identifier=MT-HTTP"
    assert log =~ "observability_api_request_completed method=POST path=/api/v1/refresh status=202"
    assert log =~ "observability_api_request_completed method=GET path=/api/v1/MT-MISSING status=404"
    assert log =~ "observability_api_request_completed method=POST path=/api/v1/state status=405"
  end

  test "phoenix observability api emits request failure events" do
    exploding_orchestrator = __MODULE__.ExplodingObservabilityApiOrchestrator
    start_supervised!({ExplodingOrchestrator, name: exploding_orchestrator})
    start_test_endpoint(orchestrator: exploding_orchestrator, snapshot_timeout_ms: 50)

    log =
      capture_log(fn ->
        assert_raise ArgumentError, fn ->
          get(build_conn(), "/api/v1/state")
        end
      end)

    assert log =~ "observability_api_request_failed method=GET path=/api/v1/state"
    assert log =~ "not a list"
  end

  test "dashboard bootstraps liveview from embedded static assets" do
    orchestrator_name = __MODULE__.AssetOrchestrator

    {:ok, _pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: static_snapshot(),
        refresh: %{
          queued: true,
          coalesced: false,
          requested_at: DateTime.utc_now(),
          operations: ["poll"]
        }
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    html = html_response(get(build_conn(), "/"), 200)
    assert html =~ "/dashboard.css"
    assert html =~ "/vendor/phoenix_html/phoenix_html.js"
    assert html =~ "/vendor/phoenix/phoenix.js"
    assert html =~ "/vendor/phoenix_live_view/phoenix_live_view.js"
    assert html =~ ~s(href="/source")
    refute html =~ "/assets/app.js"
    refute html =~ "<style>"

    dashboard_css = response(get(build_conn(), "/dashboard.css"), 200)
    assert dashboard_css =~ ":root {"
    assert dashboard_css =~ ".status-badge-live"
    assert dashboard_css =~ ".app-footer"
    assert dashboard_css =~ "[data-phx-main].phx-connected .status-badge-live"
    assert dashboard_css =~ "[data-phx-main].phx-connected .status-badge-offline"

    phoenix_html_js = response(get(build_conn(), "/vendor/phoenix_html/phoenix_html.js"), 200)
    assert phoenix_html_js =~ "phoenix.link.click"

    phoenix_js = response(get(build_conn(), "/vendor/phoenix/phoenix.js"), 200)
    assert phoenix_js =~ "var Phoenix = (() => {"

    live_view_js =
      response(get(build_conn(), "/vendor/phoenix_live_view/phoenix_live_view.js"), 200)

    assert live_view_js =~ "var LiveView = (() => {"
  end

  test "source notice exposes AGPL source availability metadata" do
    start_test_endpoint([])

    with_env(
      %{
        "MAESTRO_SOURCE_URL" => "https://example.com/acme/maestro-source",
        "MAESTRO_SOURCE_REVISION" => "abc123"
      },
      fn ->
        html = html_response(get(build_conn(), "/source"), 200)

        assert html =~ "Maestro Source Code"
        assert html =~ "AGPL-3.0-only"
        assert html =~ "https://example.com/acme/maestro-source"
        assert html =~ "abc123"
        assert html =~ "LICENSES/Apache-2.0.txt"
        assert html =~ "MODIFICATIONS.md"
        assert html =~ "SOURCE.md"
        assert html =~ "THIRD_PARTY_LICENSES.md"

        payload = json_response(get(build_conn(), "/api/v1/source"), 200)

        assert payload == %{
                 "license" => "AGPL-3.0-only",
                 "source_url" => "https://example.com/acme/maestro-source",
                 "source_revision" => "abc123",
                 "notice_path" => "/source",
                 "inherited_license_file" => "LICENSES/Apache-2.0.txt",
                 "modification_notice_file" => "MODIFICATIONS.md",
                 "source_guidance_file" => "SOURCE.md",
                 "third_party_license_file" => "THIRD_PARTY_LICENSES.md"
               }

        assert json_response(post(build_conn(), "/api/v1/source", %{}), 405) ==
                 %{"error" => %{"code" => "method_not_allowed", "message" => "Method not allowed"}}
      end
    )
  end

  test "dashboard liveview renders and refreshes over pubsub" do
    orchestrator_name = __MODULE__.DashboardOrchestrator
    snapshot = static_snapshot()

    SymphonyElixir.Observability.EventStore.reset()

    capture_log(fn ->
      SymphonyElixir.Observability.Logger.emit(:info, :codex_turn_started, %{
        component: "codex.app_server",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        thread_id: "thread-http",
        turn_id: "turn-1"
      })

      SymphonyElixir.Observability.Logger.emit(:info, :tool_call_succeeded, %{
        component: "agent.dynamic_tool_bridge",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        tool_name: "repo_change_proposal_snapshot",
        dynamic_tool_usage_kind: "typed",
        dynamic_tool_workflow_capability: "repo.change_proposal_snapshot",
        dynamic_tool_provider_capability_unavailable: [
          %{
            "workflowCapability" => "repo.submit_change_proposal_review",
            "reason" => "provider_capability_not_available",
            "description" => "formal PR reviews"
          }
        ]
      })
    end)

    {:ok, orchestrator_pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: snapshot,
        refresh: %{
          queued: true,
          coalesced: true,
          requested_at: DateTime.utc_now(),
          operations: ["poll"]
        }
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    {:ok, view, html} = live(build_conn(), "/")
    assert html =~ "Operations Dashboard"
    assert html =~ "MT-HTTP"
    assert html =~ "MT-RETRY"
    assert html =~ "rendered"
    assert html =~ "Runtime"
    assert html =~ "Live"
    assert html =~ "Offline"
    assert html =~ "Copy ID"
    assert html =~ "Agent update"
    assert html =~ "Recent events"
    assert html =~ "Dynamic tools"
    assert html =~ "Typed hits"
    assert html =~ "Raw attempts"
    assert html =~ "Operator alerts"
    assert html =~ "Known provider capability unavailable reports"
    assert html =~ "repo.submit_change_proposal_review"
    assert html =~ "Live details"
    assert html =~ "codex_turn_started"
    refute html =~ "data-runtime-clock="
    refute html =~ "setInterval(refreshRuntimeClocks"
    refute html =~ "Refresh now"
    refute html =~ "Transport"
    assert html =~ "status-badge-live"
    assert html =~ "status-badge-offline"

    updated_snapshot =
      put_in(snapshot.running, [
        %{
          issue_id: "issue-http",
          identifier: "MT-HTTP",
          state: "In Progress",
          session_id: "thread-http",
          turn_count: 8,
          last_agent_event: :notification,
          last_agent_message: %{
            event: :notification,
            message: %{
              payload: %{
                "method" => "codex/event/agent_message_content_delta",
                "params" => %{
                  "msg" => %{
                    "content" => "structured update"
                  }
                }
              }
            }
          },
          last_agent_timestamp: DateTime.utc_now(),
          agent_input_tokens: 10,
          agent_output_tokens: 12,
          agent_total_tokens: 22,
          started_at: DateTime.utc_now()
        }
      ])

    :sys.replace_state(orchestrator_pid, fn state ->
      Keyword.put(state, :snapshot, updated_snapshot)
    end)

    StatusDashboard.notify_update()

    assert_eventually(fn ->
      render(view) =~ "agent message content streaming: structured update"
    end)
  end

  test "dashboard liveview renders issue-scoped structured history" do
    orchestrator_name = __MODULE__.DashboardIssueOrchestrator
    snapshot = static_snapshot()

    SymphonyElixir.Observability.EventStore.reset()

    capture_log(fn ->
      SymphonyElixir.Observability.Logger.emit(:info, :workspace_prepare_started, %{
        component: "workspace",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        workspace_path: Path.join(Config.settings!().workspace.root, "MT-HTTP")
      })

      SymphonyElixir.Observability.Logger.emit(:info, :codex_session_started, %{
        component: "codex.app_server",
        run_id: "run-http",
        session_id: "thread-http",
        thread_id: "thread-http"
      })

      SymphonyElixir.Observability.Logger.emit(:info, :codex_turn_started, %{
        component: "codex.app_server",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        thread_id: "thread-http",
        turn_id: "turn-1"
      })

      SymphonyElixir.Observability.Logger.emit(:warning, :tool_call_rejected, %{
        component: "agent.dynamic_tool_bridge",
        issue_id: "issue-http",
        issue_identifier: "MT-HTTP",
        run_id: "run-http",
        session_id: "thread-http",
        tool_name: "linear_graphql",
        dynamic_tool_usage_kind: "raw",
        dynamic_tool_failure_reason: "unsupported_tool"
      })
    end)

    {:ok, _pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: snapshot,
        refresh: %{
          queued: true,
          coalesced: false,
          requested_at: DateTime.utc_now(),
          operations: ["poll"]
        }
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    {:ok, _view, html} = live(build_conn(), "/issues/MT-HTTP")

    assert html =~ "Issue MT-HTTP"
    assert html =~ "Back to dashboard"
    assert html =~ "JSON details"
    assert html =~ "Recent structured events"
    assert html =~ "Agent session logs"
    assert html =~ "Dynamic tools"
    assert html =~ "Operator alerts"
    assert html =~ "Normal workflow sessions must not attempt raw or non-planned tools."
    assert html =~ "Unsupported tool calls indicate an agent/tool-surface regression."
    assert html =~ "workspace_prepare_started"
    assert html =~ "codex_session_started"
    assert html =~ "codex_turn_started"
    assert html =~ "thread-http"
  end

  test "dashboard liveview emits mount lifecycle events" do
    orchestrator_name = __MODULE__.DashboardLiveMountOrchestrator

    {:ok, _pid} =
      StaticOrchestrator.start_link(
        name: orchestrator_name,
        snapshot: static_snapshot(),
        refresh: %{
          queued: true,
          coalesced: false,
          requested_at: DateTime.utc_now(),
          operations: ["poll"]
        }
      )

    start_test_endpoint(orchestrator: orchestrator_name, snapshot_timeout_ms: 50)

    log =
      capture_log(fn ->
        {:ok, _view, html} = live(build_conn(), "/")
        assert html =~ "Operations Dashboard"
      end)

    assert log =~ "dashboard_live_mounted"
    assert log =~ "subscription=ok"
  end

  test "dashboard liveview renders an unavailable state without crashing" do
    start_test_endpoint(
      orchestrator: __MODULE__.MissingDashboardOrchestrator,
      snapshot_timeout_ms: 5
    )

    {:ok, _view, html} = live(build_conn(), "/")
    assert html =~ "Snapshot unavailable"
    assert html =~ "snapshot_unavailable"
  end

  test "dashboard liveview degrades gracefully when payload projection fails" do
    exploding_orchestrator = __MODULE__.ExplodingDashboardLiveOrchestrator
    start_supervised!({ExplodingOrchestrator, name: exploding_orchestrator})
    start_test_endpoint(orchestrator: exploding_orchestrator, snapshot_timeout_ms: 50)

    log =
      capture_log(fn ->
        {:ok, _view, html} = live(build_conn(), "/")
        assert html =~ "Snapshot unavailable"
        assert html =~ "snapshot_projection_failed"
        assert html =~ "Dashboard snapshot projection failed"
      end)

    assert log =~ "dashboard_live_payload_load_failed"
    assert log =~ "not a list"
  end

  test "http server serves embedded assets, accepts form posts, and rejects invalid hosts" do
    spec = HttpServer.child_spec(port: 0)
    assert spec.id == HttpServer
    assert spec.start == {HttpServer, :start_link, [[port: 0]]}

    assert :ignore = HttpServer.start_link(port: nil)
    assert HttpServer.bound_port() == nil

    snapshot = static_snapshot()
    orchestrator_name = __MODULE__.BoundPortOrchestrator

    refresh = %{
      queued: true,
      coalesced: false,
      requested_at: DateTime.utc_now(),
      operations: ["poll"]
    }

    server_opts = [
      host: "127.0.0.1",
      port: 0,
      orchestrator: orchestrator_name,
      snapshot_timeout_ms: 50
    ]

    start_supervised!({StaticOrchestrator, name: orchestrator_name, snapshot: snapshot, refresh: refresh})

    start_supervised!({HttpServer, server_opts})

    port = wait_for_bound_port()
    assert port == HttpServer.bound_port()

    response = Req.get!("http://127.0.0.1:#{port}/api/v1/state")
    assert response.status == 200
    assert response.body["counts"] == %{"running" => 1, "retrying" => 1}

    dashboard_css = Req.get!("http://127.0.0.1:#{port}/dashboard.css")
    assert dashboard_css.status == 200
    assert dashboard_css.body =~ ":root {"

    phoenix_js = Req.get!("http://127.0.0.1:#{port}/vendor/phoenix/phoenix.js")
    assert phoenix_js.status == 200
    assert phoenix_js.body =~ "var Phoenix = (() => {"

    refresh_response =
      Req.post!("http://127.0.0.1:#{port}/api/v1/refresh",
        headers: [{"content-type", "application/x-www-form-urlencoded"}],
        body: ""
      )

    assert refresh_response.status == 202
    assert refresh_response.body["queued"] == true

    method_not_allowed_response =
      Req.post!("http://127.0.0.1:#{port}/api/v1/state",
        headers: [{"content-type", "application/x-www-form-urlencoded"}],
        body: ""
      )

    assert method_not_allowed_response.status == 405
    assert method_not_allowed_response.body["error"]["code"] == "method_not_allowed"

    assert {:error, _reason} = HttpServer.start_link(host: "bad host", port: 0)
  end

  test "http server emits lifecycle events" do
    snapshot = static_snapshot()
    orchestrator_name = __MODULE__.HttpServerEventsOrchestrator

    refresh = %{
      queued: true,
      coalesced: false,
      requested_at: DateTime.utc_now(),
      operations: ["poll"]
    }

    start_supervised!({StaticOrchestrator, name: orchestrator_name, snapshot: snapshot, refresh: refresh})

    start_log =
      capture_log(fn ->
        start_supervised!(
          {HttpServer,
           [
             host: "127.0.0.1",
             port: 0,
             orchestrator: orchestrator_name,
             snapshot_timeout_ms: 50
           ]}
        )

        assert is_integer(wait_for_bound_port())
      end)

    ignored_log =
      capture_log(fn ->
        assert :ignore = HttpServer.start_link(port: nil)
      end)

    failed_log =
      capture_log(fn ->
        assert {:error, _reason} = HttpServer.start_link(host: "bad host", port: 0)
      end)

    assert start_log =~ "http_server_started"
    assert start_log =~ "requested_port=0"
    assert ignored_log =~ "http_server_ignored"
    assert ignored_log =~ "reason=invalid_port"
    assert failed_log =~ "http_server_start_failed"
    assert failed_log =~ "bad host"
  end

  defp start_test_endpoint(overrides) do
    endpoint_config =
      :symphony_elixir
      |> Application.get_env(SymphonyElixirWeb.Endpoint, [])
      |> Keyword.merge(server: false, secret_key_base: String.duplicate("s", 64))
      |> Keyword.merge(overrides)

    Application.put_env(:symphony_elixir, SymphonyElixirWeb.Endpoint, endpoint_config)
    start_supervised!({SymphonyElixirWeb.Endpoint, []})
  end

  defp with_env(env, fun) when is_map(env) and is_function(fun, 0) do
    previous = Map.new(Map.keys(env), &{&1, System.get_env(&1)})

    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)

    try do
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp static_snapshot do
    %{
      running: [
        %{
          issue_id: "issue-http",
          identifier: "MT-HTTP",
          run_id: "run-http",
          state: "In Progress",
          session_id: "thread-http",
          turn_count: 7,
          agent_provider_kind: "codex",
          agent_process_pid: nil,
          last_agent_message: "rendered",
          last_agent_timestamp: nil,
          last_agent_event: :notification,
          agent_input_tokens: 4,
          agent_output_tokens: 8,
          agent_total_tokens: 12,
          started_at: DateTime.utc_now()
        }
      ],
      retrying: [
        %{
          issue_id: "issue-retry",
          identifier: "MT-RETRY",
          attempt: 2,
          due_in_ms: 2_000,
          error: "boom"
        }
      ],
      agent_totals: %{input_tokens: 4, output_tokens: 8, total_tokens: 12, seconds_running: 42.5},
      agent_rate_limits: %{"primary" => %{"remaining" => 11}}
    }
  end

  defp wait_for_bound_port do
    assert_eventually(fn ->
      is_integer(HttpServer.bound_port())
    end)

    HttpServer.bound_port()
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition not met in time")

  defp ensure_workflow_store_running do
    if Process.whereis(WorkflowStore) do
      :ok
    else
      :ok = restart_supervised_child(WorkflowStore)
    end
  end

  defp explicit_linear_tracker do
    %{
      kind: "linear",
      endpoint: "https://api.linear.app/graphql",
      auth: %{"api_key" => "linear-token"},
      provider: %{"project_slug" => "PROJ"},
      lifecycle: %{
        "active_states" => ["Todo"],
        "terminal_states" => ["Done"],
        "state_phase_map" => %{
          "Todo" => "todo",
          "Done" => "done"
        }
      }
    }
  end

  defp assert_tracker_error({:error, %TrackerError{} = error}, operation, code, source_reason) do
    assert error.provider == "linear"
    assert error.operation == operation
    assert error.code == code
    assert error.details[:source_reason] == source_reason
  end
end
