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

  test "owner DOWN cleans an active provider session from the monitor process" do
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
    assert Keyword.fetch!(stop_opts, :status) == :failed
    assert Keyword.fetch!(stop_opts, :issue) == issue
    assert Keyword.fetch!(stop_opts, :error) =~ "shutdown"
  end
end
