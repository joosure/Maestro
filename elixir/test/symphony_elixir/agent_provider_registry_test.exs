defmodule SymphonyElixir.AgentProviderRegistryTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.{ClaudeCode, Codex, Mock, OpenCode}
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyElixir.AgentProvider.{EventSummary, Session, TurnResult}
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Platform.CommandEnv

  defmodule OpenCodeTestPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      conn = fetch_query_params(conn)
      {:ok, body, conn} = read_body(conn)
      send(opts[:owner], {:opencode_request, %{method: conn.method, path: conn.request_path, body: body}})

      case {conn.method, conn.request_path} do
        {"GET", "/global/health"} ->
          json(conn, 200, %{"healthy" => true})

        {"GET", "/global/event"} ->
          conn = put_resp_header(conn, "content-type", "text/event-stream")
          conn = send_chunked(conn, 200)
          {:ok, conn} = chunk(conn, Keyword.get(opts, :event_body, ""))
          conn

        {"POST", "/session/opencode-session-1/permissions/" <> _permission_id} ->
          json(conn, 200, %{"ok" => true})

        {"POST", "/session"} ->
          json(conn, 200, %{"id" => "opencode-session-1"})

        {"POST", "/session/opencode-session-1/message"} ->
          Process.sleep(Keyword.get(opts, :message_delay_ms, 0))
          json(conn, 200, %{"info" => %{"id" => "opencode-turn-1", "tokens" => %{"input" => 4, "output" => 5, "reasoning" => 6}}})

        {"POST", "/session/opencode-session-1/abort"} ->
          json(conn, 200, %{"ok" => true})

        _ ->
          json(conn, 404, %{"error" => "not found"})
      end
    end

    defp json(conn, status, payload) do
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(status, Jason.encode!(payload))
    end
  end

  defmodule FakeAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    def kind, do: "fake"
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def start_session(%ProviderConfig{} = config, workspace, opts \\ []) do
      send(self(), {:fake_start_session, config, workspace, opts})
      {:ok, Session.new(agent_provider_kind: "fake", provider_state: %{workspace: workspace}, workspace: workspace)}
    end

    def run_turn(%ProviderConfig{} = config, session, prompt, issue, opts \\ []) do
      send(self(), {:fake_run_turn, config, session, prompt, issue, opts})
      {:ok, TurnResult.new(session_id: "fake-session", thread_id: "fake-thread", turn_id: "fake-turn")}
    end

    def stop_session(%ProviderConfig{} = config, session, opts \\ []) do
      send(self(), {:fake_stop_session, config, session, opts})
      :ok
    end

    def session_stop_options(%ProviderConfig{}, _result, issue), do: [issue: issue, fake: true]

    def failed_session_stop_options(%ProviderConfig{}, issue, error),
      do: [status: :failed, issue: issue, extra: %{error: error}]

    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".fake-agent"
  end

  defmodule RemoteFakeAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    def kind, do: "remote_fake"
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run", "agent.runtime.remote_worker"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def start_session(%ProviderConfig{} = config, workspace, opts \\ []) do
      send(self(), {:remote_fake_start_session, config, workspace, opts})
      {:ok, Session.new(agent_provider_kind: "remote_fake", provider_state: %{workspace: workspace}, workspace: workspace)}
    end

    def run_turn(%ProviderConfig{}, _session, _prompt, _issue, _opts \\ []),
      do: {:ok, TurnResult.new(session_id: "remote-fake-session")}

    def stop_session(%ProviderConfig{}, _session, _opts \\ []), do: :ok
    def session_stop_options(%ProviderConfig{}, _result, issue), do: [issue: issue]
    def failed_session_stop_options(%ProviderConfig{}, issue, error), do: [issue: issue, extra: %{error: error}]
    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "remote_fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".remote-fake-agent"
  end

  defmodule CredentialAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    alias SymphonyElixir.Agent.Credential.{Lease, Material}

    def kind, do: "credential_fake"
    def defaults, do: %{"credential_ref" => nil}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run", "agent.credentials.managed"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def materialize_credential(%ProviderConfig{} = config, %Lease{} = lease, opts) do
      send(self(), {:credential_materialized, config, lease, opts})

      {:ok,
       Material.new(
         env: %{"MANAGED_TOKEN" => "managed-secret"},
         summary: %{source: "test-store"}
       )}
    end

    def start_session(%ProviderConfig{} = config, workspace, opts \\ []) do
      send(self(), {:credential_start_session, config, workspace, opts})
      {:ok, Session.new(agent_provider_kind: "credential_fake", provider_state: %{}, workspace: workspace)}
    end

    def run_turn(%ProviderConfig{}, _session, _prompt, _issue, _opts \\ []),
      do: {:ok, TurnResult.new(session_id: "credential-session")}

    def stop_session(%ProviderConfig{}, _session, _opts \\ []), do: :ok
    def session_stop_options(%ProviderConfig{}, _result, _issue), do: []
    def failed_session_stop_options(%ProviderConfig{}, _issue, _error), do: []
    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "credential_fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".credential-agent"
  end

  defmodule QuotaAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    alias SymphonyElixir.Agent.Quota.Snapshot

    def kind, do: "quota_fake"
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%ProviderConfig{}), do: :ok
    def capabilities, do: ["agent.turn.run", "agent.quota.probe"]
    def prepare_workspace(%ProviderConfig{}, _workspace, _opts \\ []), do: :ok

    def quota_probe(%ProviderConfig{} = config, lease, opts) do
      send(self(), {:quota_probe, config, lease, opts})
      {:ok, Snapshot.new(provider_kind: "quota_fake", status: :healthy, remaining: 42, limit: 100)}
    end

    def start_session(%ProviderConfig{} = config, workspace, opts \\ []) do
      send(self(), {:quota_start_session, config, workspace, opts})
      {:ok, Session.new(agent_provider_kind: "quota_fake", provider_state: %{}, workspace: workspace)}
    end

    def run_turn(%ProviderConfig{}, _session, _prompt, _issue, _opts \\ []),
      do: {:ok, TurnResult.new(session_id: "quota-session")}

    def stop_session(%ProviderConfig{}, _session, _opts \\ []), do: :ok
    def session_stop_options(%ProviderConfig{}, _result, _issue), do: []
    def failed_session_stop_options(%ProviderConfig{}, _issue, _error), do: []
    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: "quota_fake")
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".quota-agent"
  end

  defmodule DynamicToolTrackerAdapter do
    @behaviour SymphonyElixir.Tracker.Adapter

    def kind, do: "dynamic_tool_tracker"
    def defaults, do: %{}
    def validate_config(_tracker), do: :ok

    def dynamic_tools(_tracker) do
      [
        %{
          "name" => "ticket_lookup",
          "description" => "Execute a tracker-neutral dynamic tool spec.",
          "inputSchema" => %{
            "type" => "object",
            "required" => ["identifier"],
            "properties" => %{"identifier" => %{"type" => "string"}}
          }
        }
      ]
    end

    def tool_environment(_tracker), do: %{"FAKE_TRACKER_TOOL_ENV" => "dynamic-tool-token"}
  end

  test "defaults to codex and treats nil provider kind as unset" do
    assert AgentProvider.current_kind() == "codex"
    assert AgentProvider.current_kind(kind: nil) == "codex"
    assert AgentProvider.adapter(kind: nil) == Codex.Adapter
    assert "codex" in AgentProvider.Registry.supported_kinds()
    assert "agent.turn.run" in Codex.Adapter.capabilities()
    assert "agent.session.stateful" in Codex.Adapter.capabilities()
    assert "agent.runtime.remote_worker" in Codex.Adapter.capabilities()
    assert "agent.credentials.managed" in Codex.Adapter.capabilities()
    refute "agent.quota.probe" in Codex.Adapter.capabilities()
  end

  test "bundled provider adapters are registered through the facade" do
    supported_kinds = AgentProvider.Registry.supported_kinds()

    assert "claude_code" in supported_kinds
    assert "mock" in supported_kinds
    assert "opencode" in supported_kinds
    assert AgentProvider.adapter_for("claude_code") == ClaudeCode.Adapter
    assert AgentProvider.adapter_for("mock") == Mock.Adapter
    assert AgentProvider.adapter_for("opencode") == OpenCode.Adapter

    for adapter <- [ClaudeCode.Adapter, OpenCode.Adapter] do
      assert "agent.turn.run" in adapter.capabilities()
      assert "agent.session.stateful" in adapter.capabilities()
      assert "agent.events.streaming" in adapter.capabilities()
      assert "agent.usage.metrics" in adapter.capabilities()
      refute "agent.tools.dynamic" in adapter.capabilities()
    end

    assert "agent.runtime.remote_worker" in ClaudeCode.Adapter.capabilities()
    assert "agent.credentials.managed" in ClaudeCode.Adapter.capabilities()
    assert "agent.quota.probe" in ClaudeCode.Adapter.capabilities()
    assert "agent.credentials.managed" in Codex.Adapter.capabilities()
    refute "agent.runtime.remote_worker" in OpenCode.Adapter.capabilities()
    assert "agent.credentials.managed" in OpenCode.Adapter.capabilities()
    refute "agent.quota.probe" in OpenCode.Adapter.capabilities()
    assert Mock.Adapter.capabilities() == ["agent.turn.run"]
    refute "agent.session.stateful" in Mock.Adapter.capabilities()
    refute "agent.credentials.managed" in Mock.Adapter.capabilities()

    assert ClaudeCode.Adapter.defaults()["prompt_transport"] == "stream_json"
    assert OpenCode.Adapter.defaults()["prompt_transport"] == "http_sse"
  end

  test "provider capability claims have matching optional callbacks" do
    for {kind, adapter} <- AgentProvider.Registry.adapters() do
      capabilities = adapter.capabilities()

      if "agent.credentials.managed" in capabilities do
        assert function_exported?(adapter, :materialize_credential, 3),
               "#{kind} claims agent.credentials.managed but does not implement materialize_credential/3"
      end

      if "agent.quota.probe" in capabilities do
        assert function_exported?(adapter, :quota_probe, 3),
               "#{kind} claims agent.quota.probe but does not implement quota_probe/3"
      end
    end
  end

  test "provider adapters own only workspace automation destination directories" do
    assert SymphonyElixir.AgentProvider.Codex.Adapter.workspace_automation_destination_dir() == ".codex"
    assert SymphonyElixir.AgentProvider.ClaudeCode.Adapter.workspace_automation_destination_dir() == ".claude"
    assert SymphonyElixir.AgentProvider.Mock.Adapter.workspace_automation_destination_dir() == ".mock-agent"
    assert SymphonyElixir.AgentProvider.OpenCode.Adapter.workspace_automation_destination_dir() == ".opencode"
  end

  test "mock provider runs a completed local turn without an external process" do
    workspace = Path.join(System.tmp_dir!(), "symphony-mock-provider-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    config =
      ProviderConfig.new(%{
        kind: "mock",
        options: %{"message" => "local mock turn complete"}
      })

    assert :ok = AgentProvider.prepare_workspace(workspace, agent_provider_config: config, issue_identifier: "MEM-1")
    assert {:ok, %Session{agent_provider_kind: "mock"} = session} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-mock")

    assert session.session_id =~ "mock-session-"
    assert session.thread_id =~ "mock-thread-"

    assert {:ok, %TurnResult{status: :completed, session_id: session_id, thread_id: thread_id, turn_id: turn_id, usage: usage}} =
             AgentProvider.run_turn(
               session,
               "prompt",
               %{id: "issue-1", identifier: "MEM-1"},
               on_message: fn message -> send(self(), {:mock_agent_message, message}) end
             )

    assert session_id == session.session_id
    assert thread_id == session.thread_id
    assert turn_id =~ "mock-turn-"
    assert usage["total_tokens"] == 0

    assert_receive {:mock_agent_message,
                    %{
                      agent_provider_kind: "mock",
                      event: :mock_turn_completed,
                      payload: %{summary: "local mock turn complete", issue_identifier: "MEM-1"}
                    } = message}

    assert AgentProvider.present_message(message, kind: "mock") == "local mock turn complete"
    assert :ok = AgentProvider.stop_session(session)
  end

  test "turn result treats missing status as completed and unknown explicit status as failed" do
    assert TurnResult.new(%{}).status == :completed
    assert TurnResult.new(%{status: "future-provider-status"}).status == :failed
  end

  test "codex errors normalize to provider-neutral error shape" do
    assert %AgentProvider.Error{
             provider: "codex",
             operation: :run_turn,
             code: :agent_provider_timeout,
             retryable?: true
           } = SymphonyElixir.AgentProvider.Codex.Error.normalize(:turn_timeout, :run_turn)

    assert %AgentProvider.Error{
             provider: "codex",
             operation: :run_turn,
             code: :agent_provider_input_required,
             retryable?: false
           } =
             error =
             SymphonyElixir.AgentProvider.Codex.Error.normalize(
               {:approval_required, %{"authorization" => "Bearer secret-token"}},
               :run_turn
             )

    refute error.details.reason_summary =~ "secret-token"
  end

  test "native provider errors normalize to provider-neutral error shape" do
    existing =
      AgentProvider.Error.new(%{
        provider: "claude_code",
        operation: :run_turn,
        code: :agent_provider_timeout,
        message: "already normalized",
        retryable?: true
      })

    assert SymphonyElixir.AgentProvider.ClaudeCode.Error.normalize(existing, :start_session) == existing
    assert SymphonyElixir.AgentProvider.OpenCode.Error.normalize(existing, :start_session) == existing

    assert_native_error(
      SymphonyElixir.AgentProvider.ClaudeCode.Error.normalize(:turn_start_timeout, :run_turn),
      "claude_code",
      :run_turn,
      :agent_provider_response_timeout,
      true
    )

    for {module, provider} <- [
          {SymphonyElixir.AgentProvider.ClaudeCode.Error, "claude_code"},
          {SymphonyElixir.AgentProvider.OpenCode.Error, "opencode"}
        ] do
      assert_native_error(module.normalize(:turn_timeout, :run_turn), provider, :run_turn, :agent_provider_timeout, true)
      assert_native_error(module.normalize(:stall_timeout, :run_turn), provider, :run_turn, :agent_provider_timeout, true)
      assert_native_error(module.normalize(:bash_not_found, :start_session), provider, :start_session, :agent_provider_command_missing, false)

      missing = module.normalize({:command_not_found, "agent-with-secret-token"}, :start_session)
      assert_native_error(missing, provider, :start_session, :agent_provider_command_missing, false)
      assert missing.details.command_summary =~ "agent-with-secret-token"

      assert_native_error(module.normalize({:invalid_command, "bad\ncmd"}, :start_session), provider, :start_session, :agent_provider_command_invalid, false)
      assert_native_error(module.normalize({:invalid_command_argv, [""]}, :start_session), provider, :start_session, :agent_provider_command_invalid, false)

      assert_native_error(
        module.normalize({:unsupported_agent_provider_options, provider, ["removed_option"]}, :start_session),
        provider,
        :start_session,
        :agent_provider_config_invalid,
        false
      )

      for reason <- [
            {:invalid_workspace_cwd, :missing},
            {:invalid_workspace_cwd, :path_unreadable, "/missing"},
            {:invalid_workspace_cwd, :path_unreadable, "/missing", :enoent}
          ] do
        assert_native_error(module.normalize(reason, :start_session), provider, :start_session, :agent_provider_start_failed, false)
      end

      remote = module.normalize({:remote_unsupported, "worker.example"}, :start_session)
      assert_native_error(remote, provider, :start_session, :agent_provider_remote_unsupported, false)
      assert remote.details.worker_host == "worker.example"

      exit_error = module.normalize({:port_exit, 9}, :run_turn)
      assert_native_error(exit_error, provider, :run_turn, :agent_provider_command_exit, true)
      assert exit_error.details.exit_status == 9

      assert_native_error(module.normalize(:unexpected, :start_session), provider, :start_session, :agent_provider_start_failed, false)
      assert_native_error(module.normalize(:unexpected, :stop_session), provider, :stop_session, :agent_provider_cleanup_failed, false)
      assert_native_error(module.normalize(:unexpected, :run_turn), provider, :run_turn, :agent_provider_turn_failed, false)
    end

    claude_bridge_error =
      SymphonyElixir.AgentProvider.ClaudeCode.Error.normalize(
        :dynamic_tool_bridge_http_port_unavailable,
        :start_session
      )

    assert_native_error(
      claude_bridge_error,
      "claude_code",
      :start_session,
      :agent_provider_config_invalid,
      false
    )

    assert claude_bridge_error.message =~ "Claude Code MCP dynamic-tool bridge"
    assert claude_bridge_error.message =~ "when Dynamic Tools are enabled"
    assert claude_bridge_error.details.required_runtime == "symphony_http_server"
    assert claude_bridge_error.details.provider_requirement == "claude_code_mcp_dynamic_tools"
    assert claude_bridge_error.details.condition == "tool_context_has_tools"
    assert claude_bridge_error.details.workflow_scoped == false

    assert_native_error(
      SymphonyElixir.AgentProvider.ClaudeCode.Error.normalize({:claude_result_error, %{"is_error" => true}}, :run_turn),
      "claude_code",
      :run_turn,
      :agent_provider_turn_failed,
      false
    )

    assert_native_error(
      SymphonyElixir.AgentProvider.ClaudeCode.Error.normalize({:response_error, %{"error" => "bad"}}, :run_turn),
      "claude_code",
      :run_turn,
      :agent_provider_turn_failed,
      false
    )

    for {reason, code, retryable?} <- [
          {{:server_start_port_exit, %{message: "server exited"}}, :agent_provider_command_exit, true},
          {{:server_start_timeout, %{message: "startup timed out"}}, :agent_provider_timeout, true},
          {{:healthcheck_timeout, %{message: "health timeout"}}, :agent_provider_response_timeout, true},
          {{:healthcheck_failed, %{message: "health failed"}}, :agent_provider_start_failed, true},
          {{:session_create_timeout, %{message: "session timeout"}}, :agent_provider_response_timeout, true},
          {{:session_create_http_error, %{message: "session http failed"}}, :agent_provider_start_failed, false},
          {{:session_create_transport_error, %{message: "session transport failed"}}, :agent_provider_start_failed, true},
          {{:message_post_timeout, %{message: "message timeout"}}, :agent_provider_response_timeout, true},
          {{:message_post_http_error, %{message: "message http failed"}}, :agent_provider_turn_failed, false},
          {{:message_post_transport_error, %{message: "message transport failed"}}, :agent_provider_turn_failed, true},
          {{:event_stream_timeout, %{message: "stream timeout"}}, :agent_provider_response_timeout, true},
          {{:event_stream_failed, %{message: "stream failed"}}, :agent_provider_turn_failed, true},
          {{:turn_input_required, %{"secret" => "sk-test", "message" => "input required"}}, :agent_provider_input_required, false},
          {{:session_error, %{message: "session error"}}, :agent_provider_turn_failed, false},
          {{:message_error, %{message: "message error"}}, :agent_provider_turn_failed, false}
        ] do
      error = SymphonyElixir.AgentProvider.OpenCode.Error.normalize(reason, :run_turn)
      assert_native_error(error, "opencode", :run_turn, code, retryable?)
      refute inspect(error.details) =~ "sk-test"
    end
  end

  test "registry merges configured adapters and facade delegates to session provider" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    assert AgentProvider.adapter(kind: "fake") == FakeAdapter
    assert "fake" in AgentProvider.Registry.supported_kinds()

    workspace = Path.join(System.tmp_dir!(), "symphony-fake-provider-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    assert {:ok, session} = AgentProvider.start_session(workspace, kind: "fake", run_id: "run-1")
    assert_received {:fake_start_session, %ProviderConfig{kind: "fake"}, ^workspace, start_opts}
    assert Keyword.get(start_opts, :kind) == "fake"
    assert Keyword.get(start_opts, :run_id) == "run-1"
    runtime_context = Keyword.fetch!(start_opts, :provider_runtime_context)
    assert is_map(runtime_context)
    assert runtime_context.worker_placement == "local"

    assert %SymphonyElixir.Agent.Runtime.Target{placement: :local, workspace_path: target_workspace} =
             runtime_context.agent_runtime_target

    assert target_workspace == Path.expand(workspace)

    issue = %{id: "issue-1"}
    assert {:ok, %{session_id: "fake-session"}} = AgentProvider.run_turn(session, "prompt", issue)
    assert_received {:fake_run_turn, %ProviderConfig{kind: "fake"}, ^session, "prompt", ^issue, []}

    assert [issue: ^issue, fake: true] = AgentProvider.session_stop_options(:ok, issue, kind: "fake")
    assert [status: :failed, issue: ^issue, extra: %{error: "boom"}] = AgentProvider.failed_session_stop_options(issue, "boom", kind: "fake")

    assert :ok = AgentProvider.stop_session(session, status: :completed)
    assert_received {:fake_stop_session, %ProviderConfig{kind: "fake"}, ^session, [status: :completed]}
  end

  test "agent runtime resolves local and ssh targets with provider-neutral events" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-runtime-target-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    assert {:ok, %SymphonyElixir.Agent.Runtime.Target{} = local_target} =
             SymphonyElixir.Agent.Runtime.resolve_target(workspace,
               run_id: "run-runtime-local",
               issue_id: "issue-runtime",
               agent_provider_kind: "fake"
             )

    assert local_target.placement == :local
    assert local_target.worker_host == nil
    assert local_target.executor == SymphonyElixir.Agent.Runtime.Executor.Local

    assert {:ok, %SymphonyElixir.Agent.Runtime.Target{} = ssh_target} =
             SymphonyElixir.Agent.Runtime.resolve_target(workspace,
               worker_host: "worker.example",
               worker_pool: "coding-linux",
               run_id: "run-runtime-ssh",
               agent_provider_kind: "fake"
             )

    assert ssh_target.placement == :ssh
    assert ssh_target.worker_host == "worker.example"
    assert ssh_target.executor == SymphonyElixir.Agent.Runtime.Executor.SSH

    assert {:error, {:agent_runtime_target_invalid, :missing_worker_host, %{worker_placement: "ssh"}}} =
             SymphonyElixir.Agent.Runtime.resolve_target(workspace, agent_runtime_placement: :ssh)

    events = EventStore.recent_events(limit: 10)
    assert Enum.any?(events, &(&1["event"] == "agent_worker_selected" and &1["worker_placement"] == "local"))
    assert Enum.any?(events, &(&1["event"] == "agent_worker_selected" and &1["worker_placement"] == "ssh"))
  end

  test "agent runtime workflow config is propagated to provider executor opts" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"remote_fake" => RemoteFakeAdapter})

    token_env = "SYMPHONY_REMOTE_FAKE_DAEMON_TOKEN"
    previous_token = System.get_env(token_env)
    System.put_env(token_env, "remote-fake-secret")

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
      restore_env(token_env, previous_token)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "remote_fake",
      agent_runtime: %{
        placement: "worker_daemon",
        worker_pool: "coding-linux",
        worker_daemon: %{
          endpoint: "http://daemon-config",
          token_env: token_env,
          timeout_ms: 15_000,
          required_features: ["session_create"]
        }
      }
    )

    workspace = Path.join(System.tmp_dir!(), "symphony-runtime-config-provider-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    assert {:ok, _session} = AgentProvider.start_session(workspace)
    assert_received {:remote_fake_start_session, %ProviderConfig{kind: "remote_fake"}, ^workspace, start_opts}

    assert Keyword.fetch!(start_opts, :worker_daemon_token) == "remote-fake-secret"
    assert Keyword.fetch!(start_opts, :worker_daemon_timeout_ms) == 15_000
    assert Keyword.fetch!(start_opts, :worker_daemon_required_features) == ["session_create"]

    runtime_context = Keyword.fetch!(start_opts, :provider_runtime_context)
    assert runtime_context.worker_placement == "worker_daemon"
    assert runtime_context.worker_pool == "coding-linux"
    assert runtime_context.agent_runtime_target.metadata.worker_daemon_endpoint == "http://daemon-config"
    refute inspect(runtime_context.agent_runtime_target.metadata) =~ "remote-fake-secret"
  end

  test "providers without remote-worker capability fail before provider start" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    workspace =
      Path.join(System.tmp_dir!(), "symphony-remote-unsupported-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    config = ProviderConfig.new(%{kind: "fake", options: %{}})

    assert {:error,
            %AgentProvider.Error{
              provider: "fake",
              operation: :start_session,
              code: :agent_provider_remote_unsupported,
              retryable?: false,
              details: %{capability: "agent.runtime.remote_worker", worker_placement: "ssh", worker_host: "worker.example"}
            }} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               worker_host: "worker.example",
               run_id: "run-remote-unsupported"
             )

    refute_received {:fake_start_session, _, _, _}
  end

  test "managed credential ref fails before provider start when adapter does not claim capability" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    workspace =
      Path.join(System.tmp_dir!(), "symphony-credential-unsupported-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    config =
      ProviderConfig.new(%{
        kind: "fake",
        options: %{"credential_ref" => "credential://fake/default"}
      })

    assert {:error,
            %AgentProvider.Error{
              provider: "fake",
              operation: :start_session,
              code: :agent_provider_capability_unsupported,
              retryable?: false
            }} = AgentProvider.start_session(workspace, agent_provider_config: config, run_id: "run-credential")

    refute_received {:fake_start_session, _, _, _}

    assert Enum.any?(
             EventStore.recent_events(limit: 10),
             &(&1["event"] == "agent_credential_lease_failed" and &1["agent_provider_kind"] == "fake")
           )
  end

  test "managed credential callback materializes env before provider start when adapter claims capability" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"credential_fake" => CredentialAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    workspace =
      Path.join(System.tmp_dir!(), "symphony-credential-managed-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    config =
      ProviderConfig.new(%{
        kind: "credential_fake",
        options: %{"credential_ref" => "credential://fake/default"}
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-managed-credential",
               issue_id: "issue-managed-credential"
             )

    assert_received {:credential_materialized, %ProviderConfig{kind: "credential_fake"}, lease, materialize_opts}
    assert lease.provider_kind == "credential_fake"
    assert is_binary(lease.id)
    assert lease.credential_ref_summary != nil
    assert Keyword.get(materialize_opts, :run_id) == "run-managed-credential"

    assert_received {:credential_start_session, %ProviderConfig{kind: "credential_fake"}, ^workspace, start_opts}
    assert Keyword.get(start_opts, :agent_credential_lease).id == lease.id
    assert Keyword.get(start_opts, :agent_credential_material).env == %{"MANAGED_TOKEN" => "managed-secret"}
    assert session.agent_credential_lease.id == lease.id
    assert :ok = AgentProvider.stop_session(session, run_id: "run-managed-credential", issue_id: "issue-managed-credential")

    events = EventStore.recent_events(limit: 10)
    assert Enum.any?(events, &(&1["event"] == "agent_credential_lease_requested" and &1["agent_provider_kind"] == "credential_fake"))
    assert Enum.any?(events, &(&1["event"] == "agent_credential_lease_acquired" and &1["agent_provider_kind"] == "credential_fake"))
    assert Enum.any?(events, &(&1["event"] == "agent_credential_lease_released" and &1["lease_id"] == lease.id))
  end

  test "required quota preflight fails before provider start when adapter does not claim probe capability" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    workspace =
      Path.join(System.tmp_dir!(), "symphony-quota-required-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    config = ProviderConfig.new(%{kind: "fake", options: %{}})

    assert {:error,
            %AgentProvider.Error{
              provider: "fake",
              operation: :start_session,
              code: :agent_provider_quota_unavailable,
              retryable?: false
            }} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-quota",
               agent_quota_preflight: :required
             )

    refute_received {:fake_start_session, _, _, _}

    assert Enum.any?(
             EventStore.recent_events(limit: 10),
             &(&1["event"] == "agent_quota_probe_failed" and &1["agent_provider_kind"] == "fake")
           )
  end

  test "required quota preflight invokes provider probe callback before provider start" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"quota_fake" => QuotaAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    workspace =
      Path.join(System.tmp_dir!(), "symphony-quota-probe-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    config = ProviderConfig.new(%{kind: "quota_fake", options: %{}})

    assert {:ok, _session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-quota-probe",
               agent_quota_preflight: :required
             )

    assert_received {:quota_probe, %ProviderConfig{kind: "quota_fake"}, nil, quota_opts}
    assert Keyword.get(quota_opts, :run_id) == "run-quota-probe"

    assert_received {:quota_start_session, %ProviderConfig{kind: "quota_fake"}, ^workspace, start_opts}
    assert Keyword.get(start_opts, :agent_quota_snapshot).status == :healthy
    assert Keyword.get(start_opts, :agent_quota_snapshot).remaining == 42

    events = EventStore.recent_events(limit: 10)
    assert Enum.any?(events, &(&1["event"] == "agent_quota_probe_started" and &1["agent_provider_kind"] == "quota_fake"))
    assert Enum.any?(events, &(&1["event"] == "agent_quota_probe_completed" and &1["quota_status"] == "healthy"))
  end

  test "workflow config can select a registered non-codex provider" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{"fake" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "fake",
      agent_provider_options: %{command_argv: ["fake-agent", "run"]}
    )

    assert :ok = Config.validate!()
    assert Config.agent_provider_kind() == "fake"
    assert Config.agent_provider_settings().options == %{"command_argv" => ["fake-agent", "run"]}
    assert AgentProvider.current_kind() == "fake"
    assert AgentProvider.adapter() == FakeAdapter
  end

  test "claude_code and opencode workflow configs are validated by their adapters" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_provider_kind: "claude_code")

    assert AgentProvider.current_kind() == "claude_code"
    assert AgentProvider.adapter() == ClaudeCode.Adapter
    assert :ok = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "claude_code",
      agent_provider_options: %{command_argv: ["claude"], prompt_transport: "stream_json"}
    )

    assert :ok = Config.validate!()
    assert Config.agent_provider_kind() == "claude_code"

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_provider_kind: "opencode",
      agent_provider_options: %{command_argv: ["opencode", "serve", "--hostname", "127.0.0.1", "--port", "0"], prompt_transport: "http_sse"}
    )

    assert :ok = Config.validate!()
    assert Config.agent_provider_kind() == "opencode"
  end

  test "native app-server adapters validate provider-owned options" do
    assert :ok = ClaudeCode.Adapter.validate_options(%{})
    assert :ok = Codex.Adapter.validate_options(%{})
    assert :ok = OpenCode.Adapter.validate_options(%{})

    assert {:error, %Ecto.Changeset{valid?: false}} =
             ClaudeCode.Adapter.validate_options(%{command: "claude", command_argv: ["claude"]})

    assert {:error, {:unsupported_agent_provider_options, "opencode", ["approval_mode"]}} =
             OpenCode.Adapter.validate_options(%{command_argv: ["opencode"], approval_mode: "never"})

    assert {:error, {:unsupported_agent_provider_options, "codex", ["api_key_env"]}} =
             Codex.Adapter.validate_options(%{command_argv: ["codex"], api_key_env: "OPENAI_API_KEY"})

    assert {:error, %Ecto.Changeset{valid?: false}} =
             ClaudeCode.Adapter.validate_options(%{command_argv: ["/bin/echo"], prompt_transport: "stdin"})

    assert {:error, %Ecto.Changeset{valid?: false}} =
             OpenCode.Adapter.validate_options(%{command_argv: ["/bin/echo"], prompt_transport: "native"})

    assert {:error, %Ecto.Changeset{valid?: false}} =
             OpenCode.Adapter.validate_options(%{command_argv: ["/bin/echo"], variant: "xhigh"})

    assert {:error, %Ecto.Changeset{valid?: false}} =
             ClaudeCode.Adapter.validate_options(%{command_argv: ["/bin/echo"], effort: "extreme"})

    assert {:error, %Ecto.Changeset{valid?: false}} =
             ClaudeCode.Adapter.validate_options(%{command_argv: ["/bin/echo"], telemetry: %{enabled: "yes"}})

    assert {:error, %Ecto.Changeset{valid?: false}} =
             OpenCode.Adapter.validate_options(%{command_argv: ["/bin/echo"], telemetry: %{unsupported: true}})

    assert :ok = ClaudeCode.Adapter.validate_options(%{command_argv: ["/bin/echo"], prompt_transport: "stream_json"})

    assert :ok =
             Codex.Adapter.validate_options(%{
               command_argv: ["/bin/echo"],
               prompt_transport: "json_rpc",
               credential_ref: "credential://codex/openai"
             })

    assert :ok =
             ClaudeCode.Adapter.validate_options(%{
               command_argv: ["/bin/echo"],
               prompt_transport: "stream_json",
               effort: "max",
               telemetry: %{enabled: true, otlp_endpoint: "http://otel.example/v1/traces"}
             })

    assert :ok =
             OpenCode.Adapter.validate_options(%{
               command_argv: ["/bin/echo"],
               prompt_transport: "http_sse",
               variant: "max",
               telemetry: %{enabled: true, include_metrics: true}
             })
  end

  test "claude_code prepare workspace does not expose source tools without planned context" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-claude-tooling-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace, ".git"))
    stale_server_path = Path.join([workspace, ".symphony", "claude", "planned_tools_mcp.js"])
    File.mkdir_p!(Path.dirname(stale_server_path))
    File.write!(stale_server_path, "linear_graphql")
    on_exit(fn -> File.rm_rf(workspace) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "project",
      agent_provider_kind: "claude_code"
    )

    config = ProviderConfig.new(%{kind: "claude_code", options: %{}})

    assert :ok = AgentProvider.prepare_workspace(workspace, agent_provider_config: config, issue_identifier: "LIN-1")

    mcp_config = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "claude", "mcp.json"])))
    assert mcp_config == %{"mcpServers" => %{}}
    refute File.exists?(stale_server_path)

    assert File.read!(Path.join([workspace, ".git", "info", "exclude"])) =~ ".symphony/\n"
  end

  test "claude_code prepare workspace exposes source tools only through explicit tool_context" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-claude-tooling-all-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace, ".git"))
    on_exit(fn -> File.rm_rf(workspace) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "project",
      agent_provider_kind: "claude_code"
    )

    config = ProviderConfig.new(%{kind: "claude_code", options: %{}})
    tool_context = SymphonyElixir.Agent.DynamicTool.Context.capture([])

    assert :ok =
             AgentProvider.prepare_workspace(workspace,
               agent_provider_config: config,
               tool_context: tool_context
             )

    mcp_config = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "claude", "mcp.json"])))
    assert get_in(mcp_config, ["mcpServers", "symphony-planned-tools", "command"]) == "node"

    assert get_in(mcp_config, ["mcpServers", "symphony-planned-tools", "args"]) == [
             ".symphony/claude/planned_tools_mcp.js"
           ]

    server_path = Path.join([workspace, ".symphony", "claude", "planned_tools_mcp.js"])
    server_source = File.read!(server_path)
    refute server_source =~ "linear_graphql"
    assert server_source =~ "linear_issue_snapshot"
    assert server_source =~ "repo_checkout"
    assert server_source =~ "repo_create_or_update_change_proposal"
    assert server_source =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"
    assert server_source =~ "workspace: process.cwd()"
    refute server_source =~ "SYMPHONY_LINEAR_API_KEY"

    if node = System.find_executable("node") do
      input =
        [
          Jason.encode!(%{"jsonrpc" => "2.0", "id" => 0, "method" => "initialize", "params" => %{"protocolVersion" => "2025-11-25"}}),
          Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
        ]
        |> Enum.join("\n")
        |> Kernel.<>("\n")

      input_path = Path.join(workspace, "mcp-input.jsonl")
      File.write!(input_path, input)

      {output, 0} =
        CommandEnv.system_cmd("sh", ["-c", "cat \"$1\" | \"$2\" \"$3\"", "symphony-mcp-test", input_path, node, server_path], stderr_to_stdout: true)

      assert output =~ "\"tools\""
      refute output =~ "linear_graphql"
      assert output =~ "linear_issue_snapshot"
      assert output =~ "repo_create_or_update_change_proposal"
    end
  end

  test "claude_code runtime MCP config carries session bridge environment" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-claude-runtime-tooling-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    bridge_env = %{
      SymphonyElixir.Agent.DynamicTool.BridgeContract.base_url_env() => "http://127.0.0.1:19421/api/v1/agent-tools/dynamic",
      SymphonyElixir.Agent.DynamicTool.BridgeContract.token_env() => "session-bridge-token",
      SymphonyElixir.Agent.DynamicTool.BridgeContract.transport_env() => "local_http"
    }

    assert :ok =
             ClaudeCode.Tooling.write_runtime_mcp_config(workspace, [tool_context: dynamic_tool_context_for_test()], %{})

    empty_config = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "claude", "mcp.json"])))
    refute Map.has_key?(get_in(empty_config, ["mcpServers", "symphony-planned-tools"]), "env")
    server_path = Path.join([workspace, ".symphony", "claude", "planned_tools_mcp.js"])
    assert File.read!(server_path) =~ "fake_dynamic_tool"

    assert :ok =
             ClaudeCode.Tooling.write_runtime_mcp_config(workspace, [tool_context: dynamic_tool_context_for_test()], bridge_env)

    config = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "claude", "mcp.json"])))
    server = get_in(config, ["mcpServers", "symphony-planned-tools"])

    assert server["env"] == bridge_env
    refute inspect(config) =~ "SYMPHONY_LINEAR_API_KEY"

    assert :ok =
             ClaudeCode.Tooling.write_runtime_mcp_config(workspace, [tool_context: empty_dynamic_tool_context_for_test()], %{})

    no_tools_config = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "claude", "mcp.json"])))
    assert no_tools_config == %{"mcpServers" => %{}}
    refute File.exists?(server_path)
  end

  test "opencode prepare workspace does not expose source tools without planned context" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-opencode-tooling-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace, ".git"))
    tool_dir = Path.join([workspace, ".opencode", "tools"])
    File.mkdir_p!(tool_dir)
    File.write!(Path.join(tool_dir, "linear_graphql.ts"), "linear_graphql")
    File.write!(Path.join(tool_dir, ".symphony-planned-tools.json"), Jason.encode!(%{"files" => ["linear_graphql.ts"]}))
    on_exit(fn -> File.rm_rf(workspace) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "project",
      agent_provider_kind: "opencode"
    )

    config = ProviderConfig.new(%{kind: "opencode", options: %{}})

    assert :ok = AgentProvider.prepare_workspace(workspace, agent_provider_config: config, issue_identifier: "LIN-2")

    refute File.exists?(Path.join(tool_dir, "linear_graphql.ts"))
    refute File.exists?(Path.join(tool_dir, ".symphony-planned-tools.json"))
  end

  test "codex prepare workspace remains runtime-only and writes no dynamic tool inventory files" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-codex-tooling-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace, ".git"))
    on_exit(fn -> File.rm_rf(workspace) end)

    config = ProviderConfig.new(%{kind: "codex", options: %{}})

    assert :ok = AgentProvider.prepare_workspace(workspace, agent_provider_config: config, issue_identifier: "LIN-CODEX")
    refute File.exists?(Path.join([workspace, ".symphony", "claude", "mcp.json"]))
    refute File.exists?(Path.join([workspace, ".opencode", "tools"]))
  end

  test "claude_code and opencode tooling consume explicit planned dynamic tool context" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{
      "dynamic_tool_tracker" => DynamicToolTrackerAdapter
    })

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
    end)

    workspace =
      Path.join(System.tmp_dir!(), "symphony-dynamic-tooling-#{System.unique_integer([:positive])}")

    claude_workspace = Path.join(workspace, "claude")
    opencode_workspace = Path.join(workspace, "opencode")

    File.mkdir_p!(Path.join([claude_workspace, ".git"]))
    File.mkdir_p!(Path.join([opencode_workspace, ".git"]))
    on_exit(fn -> File.rm_rf(workspace) end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "dynamic_tool_tracker",
      tracker_api_token: nil,
      tracker_project_slug: nil
    )

    tool_context = ticket_lookup_tool_context_for_test()

    assert :ok =
             AgentProvider.prepare_workspace(claude_workspace,
               agent_provider_config: ProviderConfig.new(%{kind: "claude_code", options: %{}}),
               tool_context: tool_context,
               issue_identifier: "DYN-1"
             )

    assert :ok =
             AgentProvider.prepare_workspace(opencode_workspace,
               agent_provider_config: ProviderConfig.new(%{kind: "opencode", options: %{}}),
               tool_context: tool_context,
               issue_identifier: "DYN-2"
             )

    claude_source = File.read!(Path.join([claude_workspace, ".symphony", "claude", "planned_tools_mcp.js"]))
    opencode_source = File.read!(Path.join([opencode_workspace, ".opencode", "tools", "ticket_lookup.ts"]))

    assert claude_source =~ "Execute a tracker-neutral dynamic tool spec."
    assert opencode_source =~ "Execute a tracker-neutral dynamic tool spec."
    assert opencode_source =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN"
    refute claude_source =~ "linear_graphql"
    refute opencode_source =~ "linear_graphql"
    assert File.read!(Path.join([opencode_workspace, ".git", "info", "exclude"])) =~ ".opencode/\n"
  end

  test "claude_code prepares remote Dynamic Tool MCP tooling from planned context" do
    workspace = "/srv/symphony/workspaces/LIN-REMOTE"

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "project",
      agent_provider_kind: "claude_code"
    )

    config = ProviderConfig.new(%{kind: "claude_code", options: %{}})
    owner = self()

    remote_runner = fn script ->
      send(owner, {:claude_remote_tooling_script, script})
      {:ok, {"", 0}}
    end

    assert :ok =
             AgentProvider.prepare_workspace(workspace,
               agent_provider_config: config,
               worker_host: "worker.example",
               remote_runner: remote_runner,
               tool_context: dynamic_tool_context_for_test(),
               issue_identifier: "LIN-REMOTE"
             )

    assert_received {:claude_remote_tooling_script, script}
    assert script =~ "config_path=\"$workspace/.symphony/claude/mcp.json\""
    assert script =~ "server_path=\"$workspace/.symphony/claude/planned_tools_mcp.js\""
    assert script =~ "write_base64_file()"
    assert script =~ "base64 --decode"
    assert script =~ "command -v node"
    refute script =~ "cat > \"$config_path\""
    refute script =~ "SYMPHONY_CLAUDE_MCP_CONFIG"
    refute script =~ "SYMPHONY_CLAUDE_MCP_SERVER"

    config_source = remote_base64_file_source!(script, "$config_path")
    server_source = remote_base64_file_source!(script, "$server_path")

    assert Jason.decode!(config_source)["mcpServers"]["symphony-planned-tools"]["args"] == [
             ".symphony/claude/planned_tools_mcp.js"
           ]

    assert server_source =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"
    assert server_source =~ "fake_dynamic_tool"
    refute server_source =~ "linear_issue_snapshot"
    refute script =~ "SYMPHONY_LINEAR_API_KEY"
    refute server_source =~ "SYMPHONY_LINEAR_API_KEY"
    assert script =~ ".symphony/"
  end

  test "claude_code native adapter runs stream-json turns inside workspace" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-claude-native-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    script = Path.join(workspace, "fake-claude")

    File.write!(script, """
    #!/bin/sh
    pwd > cwd.txt
    printf '%s\\n' "$*" > claude_args.txt
    printf '%s\\n' "$SYMPHONY_LINEAR_API_KEY" > linear_api_key.txt
    printf '%s\\n' "$SYMPHONY_LINEAR_ENDPOINT" > linear_endpoint.txt
    printf '%s\\n' "$SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL" > dynamic_tool_bridge_base_url.txt
    printf '%s\\n' "$SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT" > dynamic_tool_bridge_transport.txt
    printf '%s\\n' "$OPENROUTER_API_KEY" > openrouter_api_key.txt
    printf '%s\\n' "$CLAUDE_CODE_ENABLE_TELEMETRY" > claude_code_enable_telemetry.txt
    printf '%s\\n' "$CLAUDE_CODE_ENHANCED_TELEMETRY_BETA" > claude_code_enhanced_telemetry.txt
    printf '%s\\n' "$OTEL_TRACES_EXPORTER" > otel_traces_exporter.txt
    printf '%s\\n' "$OTEL_EXPORTER_OTLP_ENDPOINT" > otel_endpoint.txt
    printf '%s\\n' "$OTEL_RESOURCE_ATTRIBUTES" > otel_resource_attributes.txt
    printf '%s\\n' "$SYMPHONY_WORKSPACE_AUTOMATION_DIR" > claude_workspace_automation_dir.txt
    IFS= read -r prompt
    printf '%s\\n' "$prompt" > prompt.json
    printf '%s\\n' 'non-json startup detail'
    printf '%s\\n' '{"type":"system","subtype":"init","session_id":"claude-real-session"}'
    printf '%s\\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"},{"type":"thinking","text":"reasoning"},{"type":"tool_use","name":"Read"},{"type":"custom","value":1}],"usage":{"input_tokens":1,"output_tokens":2,"reasoning_tokens":3}}}'
    printf '%s\\n' '{"type":"result","subtype":"success","message":{"id":"claude-message-1"},"usage":{"input_tokens":1,"output_tokens":2,"reasoning_tokens":3}}'
    """)

    File.chmod!(script, 0o755)

    config =
      ProviderConfig.new(%{
        kind: "claude_code",
        options: %{
          command_argv: [script],
          prompt_transport: "stream_json",
          effort: "high",
          telemetry: %{
            enabled: true,
            include_traces: true,
            include_metrics: false,
            include_logs: false,
            otlp_endpoint: "http://otel.example/v1",
            resource_attributes: %{team: "agent-platform"}
          },
          env: %{"OPENROUTER_API_KEY" => "openrouter-token"},
          turn_timeout_ms: 5_000,
          read_timeout_ms: 5_000
        }
      })

    issue = %{id: "issue-external", identifier: "MT-EXTERNAL", title: "Native Claude"}

    capture_log(fn ->
      assert {:ok, session} =
               AgentProvider.start_session(workspace,
                 agent_provider_config: config,
                 run_id: "run-claude",
                 issue: issue,
                 issue_id: "issue-external",
                 issue_identifier: "MT-EXTERNAL",
                 http_port: 4521
               )

      assert {:ok, result} =
               AgentProvider.run_turn(
                 session,
                 "rendered prompt",
                 issue,
                 issue_id: "issue-external",
                 issue_identifier: "MT-EXTERNAL",
                 on_message: fn message -> send(self(), {:claude_message, message}) end
               )

      assert :ok = AgentProvider.stop_session(session)
      send(self(), {:claude_native_result, session, result})
    end)

    assert_received {:claude_native_result, %Session{agent_provider_kind: "claude_code", thread_id: thread_id}, %TurnResult{} = result}
    assert is_binary(thread_id)
    assert result.turn_id == "claude-message-1"
    assert result.usage == %{input: 1, output: 2, reasoning: 3, total: 6}
    assert {:ok, canonical_workspace} = SymphonyElixir.PathSafety.canonicalize(workspace)
    assert File.read!(Path.join(workspace, "cwd.txt")) == canonical_workspace <> "\n"
    assert File.read!(Path.join(workspace, "prompt.json")) =~ "rendered prompt"
    claude_args = File.read!(Path.join(workspace, "claude_args.txt"))
    assert claude_args =~ "--input-format stream-json"
    assert claude_args =~ "--strict-mcp-config"
    assert claude_args =~ "--mcp-config .symphony/claude/mcp.json"
    assert claude_args =~ "--session-id"
    assert claude_args =~ "--effort high"
    assert claude_args =~ "--allowedTools"
    assert claude_args =~ "mcp__symphony-planned-tools__repo_checkout"
    refute claude_args =~ "mcp__symphony-planned-tools__linear_graphql"
    refute claude_args =~ "mcp__symphony-planned-tools__repo_merge_change_proposal"
    refute claude_args =~ "mcp__symphony-planned-tools__repo_close_change_proposal"
    assert File.read!(Path.join(workspace, "linear_api_key.txt")) == "\n"
    assert File.read!(Path.join(workspace, "linear_endpoint.txt")) == "\n"

    assert File.read!(Path.join(workspace, "dynamic_tool_bridge_base_url.txt")) ==
             "http://127.0.0.1:4521/api/v1/agent-tools/dynamic\n"

    assert File.read!(Path.join(workspace, "dynamic_tool_bridge_transport.txt")) == "local_http\n"
    assert File.read!(Path.join(workspace, "openrouter_api_key.txt")) == "openrouter-token\n"

    mcp_config = Jason.decode!(File.read!(Path.join([workspace, ".symphony", "claude", "mcp.json"])))
    mcp_env = get_in(mcp_config, ["mcpServers", "symphony-planned-tools", "env"])
    assert mcp_env[SymphonyElixir.Agent.DynamicTool.BridgeContract.base_url_env()] == "http://127.0.0.1:4521/api/v1/agent-tools/dynamic"
    assert mcp_env[SymphonyElixir.Agent.DynamicTool.BridgeContract.transport_env()] == "local_http"
    assert is_binary(mcp_env[SymphonyElixir.Agent.DynamicTool.BridgeContract.token_env()])

    runtime_mcp_source = File.read!(Path.join([workspace, ".symphony", "claude", "planned_tools_mcp.js"]))
    assert runtime_mcp_source =~ "repo_checkout"
    refute runtime_mcp_source =~ "linear_graphql"
    refute runtime_mcp_source =~ "repo_merge_change_proposal"
    refute runtime_mcp_source =~ "repo_close_change_proposal"

    assert File.read!(Path.join(workspace, "claude_workspace_automation_dir.txt")) ==
             Path.join(canonical_workspace, ".claude") <> "\n"

    assert File.read!(Path.join(workspace, "claude_code_enable_telemetry.txt")) == "1\n"
    assert File.read!(Path.join(workspace, "claude_code_enhanced_telemetry.txt")) == "1\n"
    assert File.read!(Path.join(workspace, "otel_traces_exporter.txt")) == "otlp\n"
    assert File.read!(Path.join(workspace, "otel_endpoint.txt")) == "http://otel.example/v1\n"
    otel_resource_attributes = File.read!(Path.join(workspace, "otel_resource_attributes.txt"))
    assert otel_resource_attributes =~ "agent.provider=claude_code"
    assert otel_resource_attributes =~ "issue.identifier=MT-EXTERNAL"
    assert otel_resource_attributes =~ "run.id=run-claude"
    assert otel_resource_attributes =~ "team=agent-platform"
    assert_received {:claude_message, %{event: :turn_started, title: "MT-EXTERNAL: Native Claude"}}
    assert_received {:claude_message, %{event: "message.part.updated", payload: %{"payload" => %{"properties" => %{"part" => %{"type" => "reasoning"}}}}}}
    assert_received {:claude_message, %{event: "message.part.updated", payload: %{"payload" => %{"properties" => %{"part" => %{"type" => "tool", "tool" => "Read"}}}}}}

    events = EventStore.recent_events(limit: 10)

    assert Enum.any?(events, &(&1["event"] == "claude_code_turn_started" and &1["agent_provider_kind"] == "claude_code"))

    assert Enum.any?(
             events,
             &(&1["event"] == "claude_code_turn_completed" and &1["agent_provider_kind"] == "claude_code")
           )
  end

  test "claude_code native adapter normalizes unsuccessful result turns" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-claude-native-error-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    script = Path.join(workspace, "fake-claude-error")

    File.write!(script, """
    #!/bin/sh
    IFS= read -r _prompt
    printf '%s\\n' '{"type":"result","subtype":"error","is_error":true,"usage":{"input_tokens":1}}'
    """)

    File.chmod!(script, 0o755)

    config =
      ProviderConfig.new(%{
        kind: "claude_code",
        options: %{command_argv: [script], prompt_transport: "stream_json", turn_timeout_ms: 5_000, read_timeout_ms: 5_000}
      })

    capture_log(fn ->
      assert {:ok, session} =
               AgentProvider.start_session(workspace,
                 agent_provider_config: config,
                 run_id: "run-claude-error",
                 http_port: 4521
               )

      assert {:error,
              %AgentProvider.Error{
                provider: "claude_code",
                operation: :run_turn,
                code: :agent_provider_turn_failed,
                retryable?: false
              }} = AgentProvider.run_turn(session, "rendered prompt", %{id: "issue-claude-error"})

      assert :ok = AgentProvider.stop_session(session, status: :failed)
    end)
  end

  test "claude_code native adapter runs remote stream-json turns through Agent.Runtime SSH executor" do
    test_root =
      Path.join(System.tmp_dir!(), "symphony-claude-remote-native-#{System.unique_integer([:positive])}")

    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file, """
    #!/bin/sh
    printf 'ARGV:%s\\n' "$*" >> "#{trace_file}"
    case " $* " in
      *" -N "*) sleep 30; exit 0 ;;
    esac
    IFS= read -r prompt
    printf 'PROMPT:%s\\n' "$prompt" >> "#{trace_file}"
    printf '%s\\n' '{"type":"result","subtype":"success","message":{"id":"remote-claude-message"},"usage":{"input_tokens":2,"output_tokens":3}}'
    """)

    workspace = "/srv/symphony/workspaces/REMOTE-CLAUDE"

    config =
      ProviderConfig.new(%{
        kind: "claude_code",
        options: %{
          command_argv: ["claude"],
          prompt_transport: "stream_json",
          env: %{"OPENROUTER_API_KEY" => "remote-openrouter-token"},
          turn_timeout_ms: 5_000,
          read_timeout_ms: 5_000
        }
      })

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               worker_host: "worker.example",
               http_port: 4521,
               tool_context: dynamic_tool_context_for_test(),
               dynamic_tool_exposure: :all,
               run_id: "run-claude-remote"
             )

    assert session.worker_host == "worker.example"
    assert session.workspace == workspace

    assert {:ok, result} =
             AgentProvider.run_turn(session, "remote rendered prompt", %{id: "issue-remote-claude"})

    assert result.turn_id == "remote-claude-message"
    assert result.usage == %{input: 2, output: 3, reasoning: 0, total: 5}
    assert :ok = AgentProvider.stop_session(session)

    trace = File.read!(trace_file)
    assert trace =~ "-o BatchMode=yes -o ExitOnForwardFailure=yes -N -T -R "
    assert trace =~ "127.0.0.1:"
    assert trace =~ ":127.0.0.1:"
    assert trace =~ "-o BatchMode=yes -T worker.example bash -lc"
    assert trace =~ "cd "
    assert trace =~ "/srv/symphony/workspaces/REMOTE-CLAUDE"
    assert trace =~ "export OPENROUTER_API_KEY="
    assert trace =~ "remote-openrouter-token"
    assert trace =~ "claude"
    assert trace =~ "--output-format"
    assert trace =~ "stream-json"
    assert trace =~ "PROMPT:{\"message\":{\"content\":\"remote rendered prompt\",\"role\":\"user\"},\"type\":\"user\"}"
  end

  test "opencode native adapter starts server session and posts turns over HTTP" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-opencode-native-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)
    store_root = Path.join(workspace, "agent_credentials")
    credential_settings = %{enabled: true, store_root: store_root, exhausted_cooldown_ms: 60_000}

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: System.tmp_dir!(),
      agent_credentials_enabled: true,
      agent_credentials_store_root: store_root,
      agent_credentials_exhausted_cooldown_ms: 60_000,
      repo_provider_kind: "cnb",
      repo_provider_repository: "acme/widgets"
    )

    {:ok, account} =
      Store.create_or_update("opencode", "openrouter", [env_name: "OPENROUTER_API_KEY"], credential_settings)

    File.write!(account.secret_file, "opencode-openrouter-token\n")

    event_body = """
    event: message.part.updated
    data: {"payload":{"type":"message.part.updated","properties":{"part":{"sessionID":"opencode-session-1","type":"step-finish","tokens":{"input":1,"output":2,"reasoning":3}}}}}

    event: message.updated
    data: {"payload":{"type":"message.updated","properties":{"info":{"sessionID":"opencode-session-1","tokens":{"input":4,"output":5,"reasoning":6}}}}}

    event: permission.asked
    data: {"payload":{"type":"permission.asked","properties":{"sessionID":"opencode-session-1","id":"perm-1","permission":"edit","patterns":["."]}}}

    """

    server_url = start_opencode_test_server!(event_body: event_body, message_delay_ms: 250)
    script = Path.join(workspace, "fake-opencode")

    File.write!(script, """
    #!/bin/sh
    pwd > opencode_cwd.txt
    printf '%s\\n' "$OPENROUTER_API_KEY" > opencode_openrouter_api_key.txt
    printf '%s\\n' "$OTEL_METRICS_EXPORTER" > opencode_otel_metrics_exporter.txt
    printf '%s\\n' "$OTEL_TRACES_EXPORTER" > opencode_otel_traces_exporter.txt
    printf '%s\\n' "$OTEL_RESOURCE_ATTRIBUTES" > opencode_otel_resource_attributes.txt
    printf '%s\\n' "$SYMPHONY_WORKSPACE_AUTOMATION_DIR" > opencode_workspace_automation_dir.txt
    printf '%s\\n' "$SYMPHONY_REPO_PROVIDER_KIND" > opencode_repo_provider_kind.txt
    printf '%s\\n' "$SYMPHONY_REPO_PROVIDER_REPOSITORY" > opencode_repo_provider_repository.txt
    printf 'opencode server listening on %s\\n' "$FAKE_OPENCODE_URL"
    while true; do sleep 1; done
    """)

    File.chmod!(script, 0o755)

    config =
      ProviderConfig.new(%{
        kind: "opencode",
        options: %{
          command_argv: [script],
          env: %{"FAKE_OPENCODE_URL" => server_url},
          credential_ref: "credential://opencode/openrouter",
          prompt_transport: "http_sse",
          variant: "max",
          telemetry: %{
            enabled: true,
            include_traces: false,
            include_metrics: true,
            include_logs: false,
            resource_attributes: %{team: "agent-platform"}
          },
          read_timeout_ms: 5_000,
          turn_timeout_ms: 5_000
        }
      })

    owner = self()
    issue = %{id: "issue-opencode", identifier: "MT-OPENCODE", title: "Native OpenCode"}

    capture_log(fn ->
      assert {:ok, session} =
               AgentProvider.start_session(workspace,
                 agent_provider_config: config,
                 run_id: "run-opencode",
                 issue: issue,
                 issue_id: "issue-opencode",
                 issue_identifier: "MT-OPENCODE",
                 agent_credentials: credential_settings,
                 http_port: 4521
               )

      assert {:ok, result} =
               AgentProvider.run_turn(
                 session,
                 "rendered opencode prompt",
                 issue,
                 on_message: fn message -> send(owner, {:opencode_message, message}) end
               )

      assert :ok = AgentProvider.stop_session(session, agent_credentials: credential_settings)
      send(self(), {:opencode_native_result, session, result})
    end)

    assert_received {:opencode_native_result, %Session{agent_provider_kind: "opencode", thread_id: "opencode-session-1", agent_credential_lease: lease}, %TurnResult{} = result}
    assert lease.account_id == "openrouter"
    assert result.turn_id == "opencode-turn-1"
    assert result.usage == %{input: 4, output: 5, reasoning: 6, total: 15}
    assert {:ok, canonical_workspace} = SymphonyElixir.PathSafety.canonicalize(workspace)
    assert_received {:opencode_request, %{method: "POST", path: "/session/opencode-session-1/message", body: body}}
    message_payload = Jason.decode!(body)
    assert message_payload["parts"] |> hd() |> Map.get("text") == "rendered opencode prompt"
    assert message_payload["variant"] == "max"
    assert File.read!(Path.join(workspace, "opencode_openrouter_api_key.txt")) == "opencode-openrouter-token\n"

    assert File.read!(Path.join(workspace, "opencode_workspace_automation_dir.txt")) ==
             Path.join(canonical_workspace, ".opencode") <> "\n"

    assert File.read!(Path.join(workspace, "opencode_repo_provider_kind.txt")) == "cnb\n"
    assert File.read!(Path.join(workspace, "opencode_repo_provider_repository.txt")) == "acme/widgets\n"
    runtime_opencode_tool = File.read!(Path.join([workspace, ".opencode", "tools", "repo_checkout.ts"]))
    assert runtime_opencode_tool =~ "repo_checkout"
    assert runtime_opencode_tool =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"

    assert runtime_opencode_tool =~
             "\"mode\": z.enum([\"create_or_switch\",\"create\",\"switch\"]).nullable().optional()"

    refute File.exists?(Path.join([workspace, ".opencode", "tools", "linear_graphql.ts"]))
    assert File.read!(Path.join(workspace, "opencode_otel_metrics_exporter.txt")) == "otlp\n"
    assert File.read!(Path.join(workspace, "opencode_otel_traces_exporter.txt")) == "\n"
    opencode_resource_attributes = File.read!(Path.join(workspace, "opencode_otel_resource_attributes.txt"))
    assert opencode_resource_attributes =~ "agent.provider=opencode"
    assert opencode_resource_attributes =~ "issue.identifier=MT-OPENCODE"
    assert opencode_resource_attributes =~ "run.id=run-opencode"
    assert opencode_resource_attributes =~ "team=agent-platform"
    assert_received {:opencode_request, %{method: "POST", path: "/session/opencode-session-1/permissions/perm-1"}}
    assert_received {:opencode_message, %{event: :turn_started, title: "MT-OPENCODE: Native OpenCode"}}
    assert_received {:opencode_message, %{event: "permission.asked"}}
  end

  test "native adapters normalize missing command and unsupported OpenCode remote workers" do
    workspace =
      Path.join(System.tmp_dir!(), "symphony-native-provider-fail-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    config = ProviderConfig.new(%{kind: "opencode", options: %{command_argv: ["missing-opencode-test-bin"]}})

    assert {:error,
            %AgentProvider.Error{
              provider: "opencode",
              operation: :start_session,
              code: :agent_provider_command_missing,
              retryable?: false
            }} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-missing",
               http_port: 4521
             )

    assert {:error,
            %AgentProvider.Error{
              provider: "opencode",
              operation: :start_session,
              code: :agent_provider_remote_unsupported,
              retryable?: false
            }} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               run_id: "run-remote",
               http_port: 4521,
               worker_host: "worker.example"
             )
  end

  defp assert_native_error(error, provider, operation, code, retryable?) do
    assert %AgentProvider.Error{
             provider: ^provider,
             operation: ^operation,
             code: ^code,
             retryable?: ^retryable?
           } = error

    assert is_binary(error.message)
    assert is_map(error.details)
    error
  end

  defp start_opencode_test_server!(opts) do
    pid =
      start_supervised!({Bandit, plug: {OpenCodeTestPlug, Keyword.put(opts, :owner, self())}, scheme: :http, port: 0, ip: {127, 0, 0, 1}})

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  defp remote_base64_file_source!(script, target) do
    pattern = ~r/write_base64_file\s+#{Regex.escape(target)}\s+'([^']+)'/
    [_, encoded] = Regex.run(pattern, script)
    Base.decode64!(encoded)
  end

  defp dynamic_tool_context_for_test do
    %{
      source_context: %{},
      tool_environment: %{},
      tool_specs: [
        %{
          "name" => "fake_dynamic_tool",
          "description" => "Fake dynamic tool used by provider integration tests.",
          "inputSchema" => %{"type" => "object"}
        }
      ]
    }
  end

  defp empty_dynamic_tool_context_for_test do
    %{
      source_context: %{},
      tool_environment: %{},
      tool_specs: [],
      tool_metadata: %{}
    }
  end

  defp ticket_lookup_tool_context_for_test do
    %{
      source_context: %{},
      tool_environment: %{},
      tool_metadata: %{},
      tool_specs: [
        %{
          "name" => "ticket_lookup",
          "description" => "Execute a tracker-neutral dynamic tool spec.",
          "inputSchema" => %{
            "type" => "object",
            "required" => ["identifier"],
            "properties" => %{"identifier" => %{"type" => "string"}}
          }
        }
      ]
    }
  end

  defp install_fake_ssh!(test_root, _trace_file, script) do
    fake_bin_dir = Path.join(test_root, "bin")
    fake_ssh = Path.join(fake_bin_dir, "ssh")

    File.mkdir_p!(fake_bin_dir)
    File.write!(fake_ssh, script)
    File.chmod!(fake_ssh, 0o755)
    System.put_env("PATH", fake_bin_dir <> ":" <> (System.get_env("PATH") || ""))
  end
end
