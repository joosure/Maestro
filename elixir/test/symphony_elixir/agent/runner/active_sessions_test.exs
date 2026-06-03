defmodule SymphonyElixir.Agent.Runner.ActiveSessionsTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Runner.ActiveSessions
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyElixir.AgentProvider.{EventSummary, Session}

  defmodule CleanupProviderAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    def kind, do: "active_cleanup_fake"
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run", "agent.session.stateful"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def start_session(%ProviderConfig{}, _workspace, _opts \\ []), do: {:error, :unused}
    def run_turn(%ProviderConfig{}, _session, _prompt, _issue, _opts \\ []), do: {:error, :unused}

    def stop_session(%ProviderConfig{} = config, session, opts \\ []) do
      send(Application.fetch_env!(:symphony_elixir, :active_sessions_test_pid), {:cleanup_stop_session, config, session, opts})
      :ok
    end

    def session_stop_options(%ProviderConfig{}, result, issue), do: [result: result, issue: issue]
    def failed_session_stop_options(%ProviderConfig{}, issue, error), do: [status: :failed, issue: issue, error: error]
    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "active_cleanup_fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".active-cleanup-fake"
  end

  test "owner shutdown cleans an active provider session without marking the provider failed" do
    server = SymphonyElixir.Agent.Runner.ActiveSessionsTest.Server
    start_supervised!({ActiveSessions, name: server})

    Application.put_env(:symphony_elixir, :active_sessions_test_pid, self())
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"active_cleanup_fake" => CleanupProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :active_sessions_test_pid)
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    issue = %{id: "issue-active-session", identifier: "AS-1"}
    config = ProviderConfig.new(%{kind: "active_cleanup_fake", options: %{}})

    session =
      Session.new(%{
        agent_provider_kind: "active_cleanup_fake",
        session_id: "active-session",
        thread_id: "active-thread",
        run_id: "run-active-session",
        workspace: "/tmp/symphony-active-session-test"
      })
      |> Session.put_config(config)

    test_pid = self()

    owner =
      spawn(fn ->
        ActiveSessions.register(
          session,
          %{issue: issue, worker_host: nil, workspace: session.workspace, run_id: session.run_id},
          server
        )

        send(test_pid, :registered)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :registered
    Process.exit(owner, :shutdown)

    assert_receive {:cleanup_stop_session, %ProviderConfig{kind: "active_cleanup_fake"}, ^session, stop_opts}, 2_000
    refute Keyword.has_key?(stop_opts, :status)
    assert Keyword.fetch!(stop_opts, :result) == :ok
    assert Keyword.fetch!(stop_opts, :issue) == issue
    refute Keyword.has_key?(stop_opts, :error)
  end

  test "orchestrator running issue termination stops an active provider session without marking the provider failed" do
    server = SymphonyElixir.Agent.Runner.ActiveSessionsTerminatedTest.Server
    start_supervised!({ActiveSessions, name: server})

    Application.put_env(:symphony_elixir, :active_sessions_test_pid, self())
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"active_cleanup_fake" => CleanupProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :active_sessions_test_pid)
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    issue = %{id: "issue-running-terminated", identifier: "AS-3"}
    config = ProviderConfig.new(%{kind: "active_cleanup_fake", options: %{}})

    session =
      Session.new(%{
        agent_provider_kind: "active_cleanup_fake",
        session_id: "active-session-terminated",
        thread_id: "active-thread-terminated",
        run_id: "run-active-session-terminated",
        workspace: "/tmp/symphony-active-session-terminated-test"
      })
      |> Session.put_config(config)

    test_pid = self()

    owner =
      spawn(fn ->
        ActiveSessions.register(
          session,
          %{issue: issue, worker_host: nil, workspace: session.workspace, run_id: session.run_id},
          server
        )

        send(test_pid, :registered)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :registered
    ActiveSessions.cleanup_owner(owner, :running_issue_terminated, server)

    assert_receive {:cleanup_stop_session, %ProviderConfig{kind: "active_cleanup_fake"}, ^session, stop_opts}, 2_000
    refute Keyword.has_key?(stop_opts, :status)
    assert Keyword.fetch!(stop_opts, :result) == :ok
    assert Keyword.fetch!(stop_opts, :issue) == issue
    refute Keyword.has_key?(stop_opts, :error)
  end

  test "owner cleanup after external cleanup is idempotent" do
    server = SymphonyElixir.Agent.Runner.ActiveSessionsIdempotentTest.Server
    start_supervised!({ActiveSessions, name: server})

    Application.put_env(:symphony_elixir, :active_sessions_test_pid, self())
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"active_cleanup_fake" => CleanupProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :active_sessions_test_pid)
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    issue = %{id: "issue-active-session-idempotent", identifier: "AS-4"}
    config = ProviderConfig.new(%{kind: "active_cleanup_fake", options: %{}})

    session =
      Session.new(%{
        agent_provider_kind: "active_cleanup_fake",
        session_id: "active-session-idempotent",
        thread_id: "active-thread-idempotent",
        run_id: "run-active-session-idempotent",
        workspace: "/tmp/symphony-active-session-idempotent-test"
      })
      |> Session.put_config(config)

    test_pid = self()

    owner =
      spawn(fn ->
        ActiveSessions.register(
          session,
          %{issue: issue, worker_host: nil, workspace: session.workspace, run_id: session.run_id},
          server
        )

        send(test_pid, :registered)

        receive do
          :claim_current_cleanup ->
            result = ActiveSessions.claim_current_cleanup(server)
            send(test_pid, {:claim_current_cleanup_result, result})
        end
      end)

    assert_receive :registered
    ActiveSessions.cleanup_owner(owner, :running_issue_terminated, server)

    assert_receive {:cleanup_stop_session, %ProviderConfig{kind: "active_cleanup_fake"}, ^session, stop_opts}, 2_000
    assert Keyword.fetch!(stop_opts, :result) == :ok

    send(owner, :claim_current_cleanup)
    assert_receive {:claim_current_cleanup_result, :not_registered}, 2_000
    refute_receive {:cleanup_stop_session, %ProviderConfig{kind: "active_cleanup_fake"}, ^session, _stop_opts}, 200
  end

  test "current owner cleanup claim pops the active session before owner exit" do
    server = SymphonyElixir.Agent.Runner.ActiveSessionsCurrentCleanupTest.Server
    start_supervised!({ActiveSessions, name: server})

    Application.put_env(:symphony_elixir, :active_sessions_test_pid, self())
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"active_cleanup_fake" => CleanupProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :active_sessions_test_pid)
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    issue = %{id: "issue-active-session-current-cleanup", identifier: "AS-5"}
    config = ProviderConfig.new(%{kind: "active_cleanup_fake", options: %{}})

    session =
      Session.new(%{
        agent_provider_kind: "active_cleanup_fake",
        session_id: "active-session-current-cleanup",
        thread_id: "active-thread-current-cleanup",
        run_id: "run-active-session-current-cleanup",
        workspace: "/tmp/symphony-active-session-current-cleanup-test"
      })
      |> Session.put_config(config)

    test_pid = self()

    owner =
      spawn(fn ->
        ActiveSessions.register(
          session,
          %{issue: issue, worker_host: nil, workspace: session.workspace, run_id: session.run_id},
          server
        )

        result = ActiveSessions.claim_current_cleanup(server)
        send(test_pid, {:claim_current_cleanup_result, result})
      end)

    assert_receive {:claim_current_cleanup_result, :ok}, 2_000

    ref = Process.monitor(owner)
    assert_receive {:DOWN, ^ref, :process, ^owner, reason}, 2_000
    assert reason in [:normal, :noproc]
    refute_receive {:cleanup_stop_session, %ProviderConfig{kind: "active_cleanup_fake"}, ^session, _stop_opts}, 200
  end

  test "external cleanup after current owner claim is idempotent" do
    server = SymphonyElixir.Agent.Runner.ActiveSessionsClaimedCleanupTest.Server
    start_supervised!({ActiveSessions, name: server})

    Application.put_env(:symphony_elixir, :active_sessions_test_pid, self())
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"active_cleanup_fake" => CleanupProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :active_sessions_test_pid)
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    issue = %{id: "issue-active-session-claimed-cleanup", identifier: "AS-6"}
    config = ProviderConfig.new(%{kind: "active_cleanup_fake", options: %{}})

    session =
      Session.new(%{
        agent_provider_kind: "active_cleanup_fake",
        session_id: "active-session-claimed-cleanup",
        thread_id: "active-thread-claimed-cleanup",
        run_id: "run-active-session-claimed-cleanup",
        workspace: "/tmp/symphony-active-session-claimed-cleanup-test"
      })
      |> Session.put_config(config)

    test_pid = self()

    owner =
      spawn(fn ->
        ActiveSessions.register(
          session,
          %{issue: issue, worker_host: nil, workspace: session.workspace, run_id: session.run_id},
          server
        )

        result = ActiveSessions.claim_current_cleanup(server)
        send(test_pid, {:claim_current_cleanup_result, result})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:claim_current_cleanup_result, :ok}, 2_000

    ActiveSessions.cleanup_owner(owner, :running_issue_terminated, server)
    refute_receive {:cleanup_stop_session, %ProviderConfig{kind: "active_cleanup_fake"}, ^session, _stop_opts}, 200

    send(owner, :stop)
  end

  test "owner crash cleans an active provider session as failed" do
    server = SymphonyElixir.Agent.Runner.ActiveSessionsCrashTest.Server
    start_supervised!({ActiveSessions, name: server})

    Application.put_env(:symphony_elixir, :active_sessions_test_pid, self())
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"active_cleanup_fake" => CleanupProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :active_sessions_test_pid)
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    issue = %{id: "issue-active-session-crash", identifier: "AS-2"}
    config = ProviderConfig.new(%{kind: "active_cleanup_fake", options: %{}})

    session =
      Session.new(%{
        agent_provider_kind: "active_cleanup_fake",
        session_id: "active-session-crash",
        thread_id: "active-thread-crash",
        run_id: "run-active-session-crash",
        workspace: "/tmp/symphony-active-session-crash-test"
      })
      |> Session.put_config(config)

    test_pid = self()

    owner =
      spawn(fn ->
        ActiveSessions.register(
          session,
          %{issue: issue, worker_host: nil, workspace: session.workspace, run_id: session.run_id},
          server
        )

        send(test_pid, :registered)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :registered
    Process.exit(owner, :boom)

    assert_receive {:cleanup_stop_session, %ProviderConfig{kind: "active_cleanup_fake"}, ^session, stop_opts}, 2_000
    assert Keyword.fetch!(stop_opts, :status) == :failed
    assert Keyword.fetch!(stop_opts, :issue) == issue
    assert Keyword.fetch!(stop_opts, :error) =~ "boom"
  end
end
