defmodule SymphonyElixir.AgentRunnerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Continuation
  alias SymphonyElixir.Agent.DynamicTool.EventContract, as: DynamicToolEventContract
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyElixir.AgentProvider.{EventSummary, Session, TurnResult}
  alias SymphonyElixir.Observability.EventStore

  defmodule FakeProviderAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    def kind, do: "fake"
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def start_session(%ProviderConfig{} = config, workspace, opts \\ []) do
      send(self(), {:fake_provider_start_session, config, workspace, opts})

      {:ok,
       Session.new(%{
         agent_provider_kind: "fake",
         agent_process_pid: "fake-provider-1",
         provider_state: %{workspace: workspace},
         run_id: Keyword.get(opts, :run_id),
         workspace: workspace
       })}
    end

    def run_turn(%ProviderConfig{} = config, session, prompt, issue, opts \\ []) do
      send(self(), {:fake_provider_run_turn, config, session, prompt, issue, opts})

      opts
      |> Keyword.fetch!(:on_message)
      |> then(fn on_message ->
        on_message.(%{
          event: :fake_progress,
          timestamp: DateTime.utc_now(),
          payload: %{usage: %{input_tokens: 1, output_tokens: 2, total_tokens: 3}},
          provider_process_pid: "fake-provider-1"
        })
      end)

      if Map.get(config.options, "emit_typed_tool_blocker") == true do
        SymphonyElixir.Observability.Logger.emit(:warning, DynamicToolEventContract.typed_tool_failure_policy_blocked_event(), %{
          component: DynamicToolEventContract.dynamic_tool_failure_policy_component(),
          issue_id: issue.id,
          run_id: session.run_id,
          resource_kind: "tracker_issue",
          resource_id: issue.id,
          tool_name: "linear_move_issue",
          error_code: "review_handoff_blocked_after_retries",
          original_error_code: "transition_readiness_not_ready",
          retryable: false
        })
      end

      {:ok, TurnResult.new(session_id: "fake-session", thread_id: "fake-thread", turn_id: "fake-turn")}
    end

    def stop_session(%ProviderConfig{} = config, session, opts \\ []) do
      send(self(), {:fake_provider_stop_session, config, session, opts})
      :ok
    end

    def session_stop_options(%ProviderConfig{}, result, issue), do: [result: result, issue_id: issue.id, fake: true]

    def failed_session_stop_options(%ProviderConfig{}, issue, error),
      do: [issue_id: issue.id, error: error, fake: true]

    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".fake-agent"
  end

  defmodule TimeoutProviderAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    def kind, do: "timeout_fake"
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run", "agent.session.stateful"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def start_session(%ProviderConfig{} = config, workspace, opts \\ []) do
      send(self(), {:timeout_provider_start_session, config, workspace, opts})

      {:ok,
       Session.new(%{
         agent_provider_kind: "timeout_fake",
         provider_state: %{workspace: workspace},
         run_id: Keyword.get(opts, :run_id),
         session_id: "timeout-session",
         thread_id: "timeout-thread",
         workspace: workspace,
         worker_host: Keyword.get(opts, :worker_host)
       })}
    end

    def run_turn(%ProviderConfig{} = config, session, prompt, issue, opts \\ []) do
      send(self(), {:timeout_provider_run_turn, config, session, prompt, issue, opts})
      {:error, :turn_timeout}
    end

    def stop_session(%ProviderConfig{} = config, session, opts \\ []) do
      send(self(), {:timeout_provider_stop_session, config, session, opts})
      :ok
    end

    def session_stop_options(%ProviderConfig{}, {:error, _reason} = result, issue),
      do: [status: :failed, result: result, issue: issue]

    def session_stop_options(%ProviderConfig{}, result, issue), do: [result: result, issue: issue]

    def failed_session_stop_options(%ProviderConfig{}, issue, error),
      do: [status: :failed, issue: issue, error: error]

    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "timeout_fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".timeout-agent"
  end

  defmodule StopFailureProviderAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    def kind, do: "stop_failure_fake"
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def start_session(%ProviderConfig{} = config, workspace, opts \\ []) do
      send(self(), {:stop_failure_provider_start_session, config, workspace, opts})

      {:ok,
       Session.new(%{
         agent_provider_kind: "stop_failure_fake",
         run_id: Keyword.get(opts, :run_id),
         session_id: "stop-failure-session",
         workspace: workspace
       })}
    end

    def run_turn(%ProviderConfig{} = config, session, prompt, issue, opts \\ []) do
      send(self(), {:stop_failure_provider_run_turn, config, session, prompt, issue, opts})
      {:ok, TurnResult.new(session_id: "stop-failure-session", turn_id: "stop-failure-turn")}
    end

    def stop_session(%ProviderConfig{} = config, session, opts \\ []) do
      send(self(), {:stop_failure_provider_stop_session, config, session, opts})
      {:error, :cleanup_boom}
    end

    def session_stop_options(%ProviderConfig{}, result, issue), do: [result: result, issue: issue]

    def failed_session_stop_options(%ProviderConfig{}, issue, error),
      do: [status: :failed, issue: issue, error: error]

    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "stop_failure_fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".stop-failure-agent"
  end

  test "runner executes through the configured provider contract" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-provider-contract-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspaces")
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
      File.rm_rf(test_root)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: workspace_root,
      agent_provider_kind: "fake",
      agent_provider_options: %{command: "fake-agent run"},
      prompt: "Runner provider contract prompt."
    )

    issue = %Issue{
      id: "issue-provider-contract",
      identifier: "MT-PROVIDER",
      title: "Run through fake provider",
      description: "Verify runner only depends on AgentProvider.Adapter.",
      state: "In Progress",
      labels: []
    }

    assert :ok =
             AgentRunner.run(issue, self(),
               issue_state_fetcher: fn ["issue-provider-contract"] ->
                 {:ok, [%{issue | state: "Done"}]}
               end
             )

    assert_received {:fake_provider_start_session, %ProviderConfig{kind: "fake"}, workspace, start_opts}
    assert Path.basename(workspace) == "MT-PROVIDER"
    assert String.ends_with?(workspace, "/workspaces/MT-PROVIDER")
    assert File.dir?(workspace)
    assert Keyword.get(start_opts, :worker_host) == nil
    assert Keyword.fetch!(start_opts, :run_id) =~ "issue-provider-contract"

    assert_received {:fake_provider_run_turn, %ProviderConfig{kind: "fake"}, session, prompt, ^issue, run_opts}
    assert session.agent_provider_kind == "fake"
    assert session.agent_process_pid == "fake-provider-1"
    assert prompt =~ "Runner provider contract prompt."
    assert is_function(Keyword.fetch!(run_opts, :on_message), 1)

    assert_received {:agent_worker_update, "issue-provider-contract",
                     %{
                       agent_provider_kind: "fake",
                       event: :fake_progress,
                       timestamp: %DateTime{},
                       provider_process_pid: "fake-provider-1"
                     }}

    assert_received {:worker_runtime_info, "issue-provider-contract",
                     %{
                       issue: %Issue{id: "issue-provider-contract", state: "Done"},
                       issue_fact_source: :agent_turn_refresh
                     }}

    assert_received {:fake_provider_stop_session, %ProviderConfig{kind: "fake"}, ^session, stop_opts}
    assert Keyword.fetch!(stop_opts, :fake) == true
    assert Keyword.fetch!(stop_opts, :issue_id) == "issue-provider-contract"
    assert Keyword.fetch!(stop_opts, :result) == :ok

    run_id = Keyword.fetch!(start_opts, :run_id)

    agent_events =
      wait_for_agent_session_events(
        %{
          issue_id: "issue-provider-contract",
          issue_identifier: "MT-PROVIDER",
          run_id: run_id
        },
        "agent_run_completed"
      )

    event_names = Enum.map(agent_events, & &1["event"])

    assert event_names == [
             "agent_run_started",
             "agent_provider_workspace_prepared",
             "agent_session_started",
             "agent_turn_started",
             "agent_turn_completed",
             "agent_cleanup_started",
             "agent_session_stopped",
             "agent_cleanup_completed",
             "agent_run_completed"
           ]

    assert Enum.count(event_names, &(&1 in ["agent_run_completed", "agent_run_failed", "agent_run_cancelled", "agent_run_retry_scheduled"])) == 1
    assert Enum.count(event_names, &(&1 in ["agent_turn_completed", "agent_turn_failed", "agent_turn_timeout", "agent_turn_input_required"])) == 1

    turn_started = Enum.find(agent_events, &(&1["event"] == "agent_turn_started"))
    assert turn_started["agent_provider_kind"] == "fake"
    assert turn_started["turn_number"] == 1
    assert turn_started["max_turns"] == Config.settings!().agent.execution.max_turns
    assert is_binary(turn_started["prompt_hash"])
    assert is_integer(turn_started["prompt_length"])
    refute Map.has_key?(turn_started, "prompt")

    session_started = Enum.find(agent_events, &(&1["event"] == "agent_session_started"))
    assert session_started["agent_provider_kind"] == "fake"
    assert session_started["stateful"] == false
    assert session_started["session_type"] == "logical"

    run_completed = List.last(agent_events)
    assert run_completed["status"] == "completed"
    assert is_integer(run_completed["duration_ms"])
  end

  test "stateless providers receive rendered workflow context on continuation turns" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-provider-stateless-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspaces")
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
      File.rm_rf(test_root)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: workspace_root,
      agent_provider_kind: "fake",
      agent_provider_options: %{command: "fake-agent run"},
      max_turns: 2,
      prompt: "Stateless workflow prompt for {{ issue.identifier }}."
    )

    issue = %Issue{
      id: "issue-stateless-continuation",
      identifier: "MT-STATELESS",
      title: "Run stateless continuation",
      description: "Keep enough context for stateless providers.",
      state: "In Progress",
      labels: []
    }

    {:ok, refresh_count} = Agent.start_link(fn -> 0 end)

    assert :ok =
             AgentRunner.run(issue, self(),
               issue_state_fetcher: fn ["issue-stateless-continuation"] ->
                 case Agent.get_and_update(refresh_count, fn count -> {count, count + 1} end) do
                   0 -> {:ok, [issue]}
                   _ -> {:ok, [%{issue | state: "Done"}]}
                 end
               end
             )

    assert_received {:fake_provider_run_turn, %ProviderConfig{kind: "fake"}, _session, first_prompt, ^issue, _run_opts}
    assert first_prompt =~ "Stateless workflow prompt for MT-STATELESS."
    refute first_prompt =~ "Stateless provider context"

    assert_received {:fake_provider_run_turn, %ProviderConfig{kind: "fake"}, _session, second_prompt, ^issue, _run_opts}
    assert second_prompt =~ "Continuation guidance:"
    assert second_prompt =~ "Stateless provider context:"
    assert second_prompt =~ "Rendered workflow prompt:"
    assert second_prompt =~ "Stateless workflow prompt for MT-STATELESS."
  end

  test "runner classifies typed tool non-retryable blocker as blocked turn without continuation" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-provider-blocked-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspaces")
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
      File.rm_rf(test_root)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: workspace_root,
      agent_provider_kind: "fake",
      agent_provider_options: %{"emit_typed_tool_blocker" => true},
      max_turns: 2,
      prompt: "Blocked provider contract prompt."
    )

    issue = %Issue{
      id: "issue-provider-blocked",
      identifier: "MT-BLOCKED",
      title: "Stop after typed tool blocker",
      description: "Verify blocked typed-tool failures stop continuation.",
      state: "In Progress",
      labels: []
    }

    assert_raise RuntimeError, ~r/Agent run failed/, fn ->
      AgentRunner.run(issue, self(),
        run_id: "run-provider-blocked",
        issue_state_fetcher: fn ["issue-provider-blocked"] ->
          {:ok, [issue]}
        end
      )
    end

    assert_received {:fake_provider_run_turn, %ProviderConfig{kind: "fake"}, _session, _prompt, ^issue, _run_opts}
    refute_received {:fake_provider_run_turn, %ProviderConfig{kind: "fake"}, _session, _prompt, ^issue, _run_opts}

    agent_events =
      wait_for_agent_session_events(
        %{
          issue_id: "issue-provider-blocked",
          issue_identifier: "MT-BLOCKED",
          run_id: "run-provider-blocked"
        },
        "agent_run_failed"
      )

    event_names = Enum.map(agent_events, & &1["event"])

    assert "agent_turn_blocked" in event_names
    refute "agent_continuation_started" in event_names

    assert Enum.any?(
             EventStore.recent_issue_events(%{issue_id: "issue-provider-blocked", run_id: "run-provider-blocked"}, limit: 20),
             &(&1["event"] == DynamicToolEventContract.typed_tool_failure_policy_blocked())
           )

    turn_blocked = Enum.find(agent_events, &(&1["event"] == "agent_turn_blocked"))
    assert turn_blocked["status"] == "blocked"
    assert turn_blocked["failure_class"] == "blocked"
    assert turn_blocked["error_code"] == "typed_tool_non_retryable_blocker"
    assert turn_blocked["retryable"] == false
    assert turn_blocked["blocker_error_code"] == "review_handoff_blocked_after_retries"
    assert turn_blocked["blocker_resource_kind"] == "tracker_issue"
    assert turn_blocked["blocker_resource_id"] == "issue-provider-blocked"

    run_failed = List.last(agent_events)
    assert run_failed["status"] == "failed"
    assert run_failed["failure_class"] == "blocked"
  end

  test "runner emits provider-neutral timeout, cleanup, and failed run events" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-provider-timeout-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspaces")
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"timeout_fake" => TimeoutProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
      File.rm_rf(test_root)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: workspace_root,
      agent_provider_kind: "timeout_fake",
      prompt: "Timeout provider contract prompt."
    )

    issue = %Issue{
      id: "issue-provider-timeout",
      identifier: "MT-TIMEOUT",
      title: "Run through timeout provider",
      description: "Verify timeout observability is provider-neutral.",
      state: "In Progress",
      labels: []
    }

    assert_raise RuntimeError, ~r/Agent run failed/, fn ->
      AgentRunner.run(issue, self(), run_id: "run-timeout")
    end

    assert_received {:timeout_provider_stop_session, %ProviderConfig{kind: "timeout_fake"}, _session, stop_opts}
    assert Keyword.fetch!(stop_opts, :status) == :failed

    agent_events =
      wait_for_agent_session_events(
        %{
          issue_id: "issue-provider-timeout",
          issue_identifier: "MT-TIMEOUT",
          run_id: "run-timeout",
          session_id: "timeout-session"
        },
        "agent_run_failed"
      )

    event_names = Enum.map(agent_events, & &1["event"])

    assert event_names == [
             "agent_run_started",
             "agent_provider_workspace_prepared",
             "agent_session_started",
             "agent_turn_started",
             "agent_turn_timeout",
             "agent_cleanup_started",
             "agent_session_stopped",
             "agent_cleanup_completed",
             "agent_run_failed"
           ]

    turn_timeout = Enum.find(agent_events, &(&1["event"] == "agent_turn_timeout"))
    assert turn_timeout["status"] == "timeout"
    assert turn_timeout["failure_class"] == "timeout"
    assert turn_timeout["error_code"] == "turn_timeout"
    assert turn_timeout["retryable"] == true

    run_failed = List.last(agent_events)
    assert run_failed["status"] == "failed"
    assert run_failed["failure_class"] == "timeout"
    assert is_integer(run_failed["duration_ms"])
  end

  test "runner emits cleanup failure without masking a successful agent turn" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-provider-stop-failure-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspaces")
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"stop_failure_fake" => StopFailureProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
      File.rm_rf(test_root)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: workspace_root,
      agent_provider_kind: "stop_failure_fake",
      prompt: "Stop failure provider contract prompt."
    )

    issue = %Issue{
      id: "issue-provider-stop-failure",
      identifier: "MT-STOPFAIL",
      title: "Run through stop failure provider",
      description: "Verify cleanup failure observability does not mask run completion.",
      state: "In Progress",
      labels: []
    }

    assert :ok =
             AgentRunner.run(issue, self(),
               run_id: "run-stop-failure",
               issue_state_fetcher: fn ["issue-provider-stop-failure"] ->
                 {:ok, [%{issue | state: "Done"}]}
               end
             )

    assert_received {:stop_failure_provider_stop_session, %ProviderConfig{kind: "stop_failure_fake"}, _session, _stop_opts}

    agent_events =
      wait_for_agent_session_events(
        %{
          issue_id: "issue-provider-stop-failure",
          issue_identifier: "MT-STOPFAIL",
          run_id: "run-stop-failure",
          session_id: "stop-failure-session"
        },
        "agent_run_completed"
      )

    event_names = Enum.map(agent_events, & &1["event"])

    assert "agent_session_stop_failed" in event_names
    assert "agent_cleanup_failed" in event_names
    assert List.last(event_names) == "agent_run_completed"

    cleanup_failed = Enum.find(agent_events, &(&1["event"] == "agent_cleanup_failed"))
    assert cleanup_failed["status"] == "failed"
    assert cleanup_failed["error"] =~ "cleanup_boom"
  end

  test "issue state refresh retries transient TAPD rate limits before continuing" do
    issue = %Issue{
      id: "tapd-issue-refresh",
      identifier: "TAPD-1",
      title: "Retry TAPD refresh",
      description: "Ensure transient TAPD refresh errors do not immediately fail a turn",
      state: "In Progress",
      url: "https://example.org/issues/TAPD-1",
      labels: []
    }

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fetcher = fn ["tapd-issue-refresh"] ->
      case Agent.get_and_update(counter, fn count -> {count, count + 1} end) do
        0 ->
          {:error, {:tapd_workflow_lookup_failed, "story", "step", {:tapd_http_status, 429, "{\"error_msg\":\"Too Many Requests\"}\n"}}}

        _ ->
          {:ok, [issue]}
      end
    end

    log =
      capture_log(fn ->
        assert {:continue, ^issue} =
                 Continuation.continue_with_issue(
                   issue,
                   fetcher,
                   issue_state_refresh_retry_delays_ms: [1]
                 )
      end)

    assert Agent.get(counter, & &1) == 2
    assert log =~ "issue_state_refresh_retry_scheduled"
  end

  test "issue state refresh uses per-issue workflow active states when deciding continuation" do
    issue = %Issue{
      id: "tapd-issue-workflow-refresh",
      identifier: "TAPD-2",
      title: "Per-type active state",
      description: "Continue when the refreshed issue stays active in its own workflow",
      state: "coding",
      workitem_type_id: "feature",
      workflow: %{
        active_states: ["coding"],
        terminal_states: ["done"],
        state_phase_map: %{"coding" => "in_progress", "done" => "done"}
      },
      url: "https://example.org/issues/TAPD-2",
      labels: []
    }

    fetcher = fn ["tapd-issue-workflow-refresh"] -> {:ok, [issue]} end

    assert {:continue, ^issue} = Continuation.continue_with_issue(issue, fetcher, [])
  end

  test "issue state refresh emits final structured failure after retry exhaustion" do
    issue = %Issue{
      id: "tapd-issue-refresh-failure",
      identifier: "TAPD-3",
      title: "Refresh failure",
      description: "Emit the final refresh failure event after retries are exhausted",
      state: "In Progress",
      url: "https://example.org/issues/TAPD-3",
      labels: []
    }

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fetcher = fn ["tapd-issue-refresh-failure"] ->
      Agent.update(counter, &(&1 + 1))
      {:error, {:tapd_request, :timeout}}
    end

    log =
      capture_log(fn ->
        assert {:error, {:issue_state_refresh_failed, {:tapd_request, :timeout}}} =
                 Continuation.continue_with_issue(
                   issue,
                   fetcher,
                   issue_state_refresh_retry_delays_ms: [1]
                 )
      end)

    assert Agent.get(counter, & &1) == 2
    assert log =~ "issue_state_refresh_retry_scheduled"
    assert log =~ "issue_state_refresh_failed"
    assert log =~ "issue_id=tapd-issue-refresh-failure"
    assert log =~ ":timeout"
  end

  test "issue state refresh retries normalized tracker errors before continuing" do
    issue = %Issue{
      id: "linear-issue-refresh",
      identifier: "LIN-1",
      title: "Retry normalized refresh",
      description: "Ensure normalized tracker errors stay retryable",
      state: "In Progress",
      url: "https://example.org/issues/LIN-1",
      labels: []
    }

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fetcher = fn ["linear-issue-refresh"] ->
      case Agent.get_and_update(counter, fn count -> {count, count + 1} end) do
        0 ->
          {:error,
           SymphonyElixir.Tracker.Error.new(%{
             provider: "linear",
             operation: :fetch_issue_states_by_ids,
             code: :http_status,
             retryable?: true,
             details: %{status: 503}
           })}

        _ ->
          {:ok, [issue]}
      end
    end

    log =
      capture_log(fn ->
        assert {:continue, ^issue} =
                 Continuation.continue_with_issue(
                   issue,
                   fetcher,
                   issue_state_refresh_retry_delays_ms: [1]
                 )
      end)

    assert Agent.get(counter, & &1) == 2
    assert log =~ "issue_state_refresh_retry_scheduled"
    assert log =~ "SymphonyElixir.Tracker.Error"
    assert log =~ "http_status"
  end

  defp wait_for_agent_session_events(context, expected_event, attempts \\ 100)

  defp wait_for_agent_session_events(context, expected_event, attempts)
       when attempts > 0 and is_map(context) and is_binary(expected_event) do
    events = EventStore.agent_session_logs(context)

    if Enum.any?(events, &(&1["event"] == expected_event)) do
      events
    else
      Process.sleep(10)
      wait_for_agent_session_events(context, expected_event, attempts - 1)
    end
  end

  defp wait_for_agent_session_events(context, expected_event, _attempts) do
    flunk("expected #{expected_event} in agent session logs, got: #{inspect(EventStore.agent_session_logs(context))}")
  end
end
