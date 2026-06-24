defmodule SymphonyWorkerDaemon.RealProviderTurnTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyElixir.HttpServer
  alias SymphonyWorkerDaemon.{Api, CapacityManager}
  alias SymphonyWorkerDaemon.Session

  @moduletag :real_provider_turn
  @moduletag timeout: 180_000

  @run_env "SYMPHONY_RUN_WORKER_DAEMON_PROVIDER_TURN"
  @dynamic_tool_run_env "SYMPHONY_RUN_WORKER_DAEMON_DYNAMIC_TOOL_TURN"
  @claude_skip_reason if(System.get_env(@run_env) != "1",
                        do: "set #{@run_env}=1 to enable authenticated Claude Code worker-daemon turn smoke tests",
                        else: if(System.find_executable("claude"), do: nil, else: "claude executable was not found in PATH")
                      )
  @claude_dynamic_tool_skip_reason (cond do
                                      System.get_env(@dynamic_tool_run_env) != "1" ->
                                        "set #{@dynamic_tool_run_env}=1 to enable authenticated Claude Code worker-daemon Dynamic Tool turn smoke tests"

                                      is_nil(System.find_executable("claude")) ->
                                        "claude executable was not found in PATH"

                                      is_nil(System.find_executable("node")) ->
                                        "node executable was not found in PATH"

                                      true ->
                                        nil
                                    end)
  @codex_skip_reason if(System.get_env(@run_env) != "1",
                       do: "set #{@run_env}=1 to enable authenticated Codex worker-daemon turn smoke tests",
                       else: if(System.find_executable("codex"), do: nil, else: "codex executable was not found in PATH")
                     )

  defmodule DynamicToolSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    @tool_name "symphony_worker_daemon_probe"

    def default_context(opts) do
      %{
        owner: Keyword.get(opts, :dynamic_tool_probe_owner) || Application.get_env(:symphony_elixir, :worker_daemon_dynamic_tool_probe_owner)
      }
    end

    def kind(_context), do: "worker_daemon_real_provider_turn_probe"

    def tools(_context, _opts) do
      [
        %{
          "name" => @tool_name,
          "description" => "Return a deterministic Worker Daemon Dynamic Tool bridge probe payload.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "request_id" => %{"type" => "string"}
            },
            "additionalProperties" => true
          }
        }
      ]
    end

    def environment(_context, _opts), do: %{}

    def execute(%{owner: owner}, tool, arguments, _opts) when is_pid(owner) do
      send(owner, {:dynamic_tool_called, tool, arguments})
      success_payload(tool, arguments)
    end

    def execute(_context, tool, arguments, _opts), do: success_payload(tool, arguments)

    defp success_payload(tool, arguments) do
      {:success,
       %{
         "probe" => "symphony-worker-daemon-dynamic-tool-ok",
         "tool" => tool,
         "arguments" => arguments
       }}
    end
  end

  @tag skip: @claude_skip_reason
  test "runs an authenticated Claude Code turn through the worker daemon" do
    claude_path = System.find_executable("claude") || flunk("claude executable was not found in PATH")
    workspace = tmp_dir!("real-claude-turn")
    port = free_port!()
    token = "real-provider-turn-token"
    ledger = unique_name("Session.Ledger")
    registry = unique_name("Registry")
    capacity = unique_name("Capacity")
    supervisor = unique_name("Session.Supervisor")

    start_supervised!({Session.Ledger, name: ledger})
    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})
    start_supervised!({Session.Supervisor, name: supervisor, session_ledger: ledger})

    start_supervised!(
      {Bandit,
       plug:
         {Api,
          [
            token: token,
            session_ledger: ledger,
            registry: registry,
            capacity_manager: capacity,
            session_supervisor: supervisor,
            workspace_roots: [workspace],
            worker_id: "real-provider-turn-worker",
            daemon_instance_id: "real-provider-turn-daemon",
            allowed_executables: [claude_path]
          ]},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: port}
    )

    config =
      ProviderConfig.new(%{
        kind: "claude_code",
        options: %{
          command_argv: [claude_path],
          prompt_transport: "stream_json",
          permission_mode: "bypassPermissions",
          turn_timeout_ms: 120_000,
          read_timeout_ms: 30_000,
          stall_timeout_ms: 60_000
        }
      })

    tool_context = empty_tool_context()

    assert :ok =
             AgentProvider.prepare_workspace(workspace,
               agent_provider_config: config,
               tool_context: tool_context
             )

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "real-provider-turn",
               worker_daemon_endpoint: "http://127.0.0.1:#{port}",
               worker_daemon_token: token,
               worker_daemon_timeout_ms: 30_000,
               tool_context: tool_context,
               run_id: "real-provider-turn-claude"
             )

    result =
      try do
        AgentProvider.run_turn(
          session,
          "Reply with exactly: symphony-worker-daemon-ok",
          %{id: "issue-real-provider-turn", identifier: "WD-REAL", title: "Worker daemon real provider turn"}
        )
      after
        AgentProvider.stop_session(session)
      end

    assert {:ok, turn_result} = result
    assert turn_result.status == :completed
    assert is_binary(turn_result.thread_id)
    assert is_binary(turn_result.turn_id)
  end

  @tag skip: @claude_dynamic_tool_skip_reason
  test "runs an authenticated Claude Code Dynamic Tool turn through worker_daemon_http" do
    claude_path = System.find_executable("claude") || flunk("claude executable was not found in PATH")
    workspace = tmp_dir!("real-claude-dynamic-tool-turn")
    daemon_port = free_port!()
    symphony_bridge_port = ensure_symphony_http_bridge!()
    token = "real-provider-dynamic-tool-turn-token"
    ledger = unique_name("Session.Ledger")
    registry = unique_name("Registry")
    capacity = unique_name("Capacity")
    supervisor = unique_name("Session.Supervisor")

    put_dynamic_tool_source!()

    start_supervised!({Session.Ledger, name: ledger})
    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})
    start_supervised!({Session.Supervisor, name: supervisor, session_ledger: ledger})

    start_supervised!(
      {Bandit,
       plug:
         {Api,
          [
            token: token,
            session_ledger: ledger,
            registry: registry,
            capacity_manager: capacity,
            session_supervisor: supervisor,
            workspace_roots: [workspace],
            worker_id: "real-provider-dynamic-tool-worker",
            daemon_instance_id: "real-provider-dynamic-tool-daemon",
            allowed_executables: [claude_path]
          ]},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: daemon_port}
    )

    config =
      ProviderConfig.new(%{
        kind: "claude_code",
        options: %{
          command_argv: [
            claude_path,
            "--allowedTools=mcp__symphony-planned-tools__symphony_worker_daemon_probe"
          ],
          prompt_transport: "stream_json",
          permission_mode: "bypassPermissions",
          turn_timeout_ms: 120_000,
          read_timeout_ms: 30_000,
          stall_timeout_ms: 60_000
        }
      })

    tool_context = dynamic_tool_context()

    assert :ok =
             AgentProvider.prepare_workspace(workspace,
               agent_provider_config: config,
               tool_context: tool_context
             )

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "real-provider-dynamic-tool-turn",
               worker_daemon_endpoint: "http://127.0.0.1:#{daemon_port}",
               worker_daemon_token: token,
               worker_daemon_timeout_ms: 30_000,
               http_port: symphony_bridge_port,
               tool_context: tool_context,
               run_id: "real-provider-dynamic-tool-turn-claude"
             )

    assert session.metadata[:dynamic_tool_bridge_transport] == "worker_daemon_http"

    result =
      try do
        AgentProvider.run_turn(
          session,
          """
          You must call the MCP Dynamic Tool named `mcp__symphony-planned-tools__symphony_worker_daemon_probe`
          with argument {"request_id": "wd-real-dynamic-tool"} before answering.
          After the tool returns, reply with exactly the `probe` value from the tool response and no other text.
          """,
          %{id: "issue-real-provider-dynamic-tool-turn", identifier: "WD-DYNAMIC", title: "Worker daemon real Dynamic Tool turn"}
        )
      after
        AgentProvider.stop_session(session)
      end

    assert {:ok, turn_result} = result
    assert turn_result.status == :completed
    assert_received {:dynamic_tool_called, "symphony_worker_daemon_probe", %{"request_id" => "wd-real-dynamic-tool"}}
  end

  @tag skip: @codex_skip_reason
  test "runs an authenticated Codex turn through the worker daemon" do
    codex_path = System.find_executable("codex") || flunk("codex executable was not found in PATH")
    workspace = runtime_tmp_dir!("real-codex-turn")
    port = free_port!()
    token = "real-provider-turn-token"
    ledger = unique_name("Session.Ledger")
    registry = unique_name("Registry")
    capacity = unique_name("Capacity")
    supervisor = unique_name("Session.Supervisor")

    start_supervised!({Session.Ledger, name: ledger})
    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})
    start_supervised!({Session.Supervisor, name: supervisor, session_ledger: ledger})

    start_supervised!(
      {Bandit,
       plug:
         {Api,
          [
            token: token,
            session_ledger: ledger,
            registry: registry,
            capacity_manager: capacity,
            session_supervisor: supervisor,
            workspace_roots: [workspace],
            worker_id: "real-provider-turn-worker",
            daemon_instance_id: "real-provider-turn-daemon",
            allowed_executables: [codex_path]
          ]},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: port}
    )

    config =
      ProviderConfig.new(%{
        kind: "codex",
        options: %{
          command_argv: [codex_path, "app-server"],
          prompt_transport: "json_rpc",
          approval_policy: "never",
          turn_timeout_ms: 120_000,
          read_timeout_ms: 30_000,
          stall_timeout_ms: 60_000
        }
      })

    tool_context = empty_tool_context()

    assert :ok =
             AgentProvider.prepare_workspace(workspace,
               agent_provider_config: config,
               tool_context: tool_context
             )

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "real-provider-turn",
               worker_daemon_endpoint: "http://127.0.0.1:#{port}",
               worker_daemon_token: token,
               worker_daemon_timeout_ms: 30_000,
               tool_context: tool_context,
               run_id: "real-provider-turn-codex"
             )

    result =
      try do
        AgentProvider.run_turn(
          session,
          "Reply with exactly: symphony-worker-daemon-ok",
          %{id: "issue-real-provider-turn-codex", identifier: "WD-REAL", title: "Worker daemon real provider turn"}
        )
      after
        AgentProvider.stop_session(session)
      end

    assert {:ok, turn_result} = result
    assert turn_result.status == :completed
    assert is_binary(turn_result.thread_id)
    assert is_binary(turn_result.turn_id)
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-worker-daemon-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp runtime_tmp_dir!(name) do
    root = SymphonyElixir.Config.settings!().workspace.root |> Path.expand()
    path = Path.join(root, "symphony-worker-daemon-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp free_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  @process_names %{
    "Session.Ledger" => __MODULE__.SessionLedger,
    "Registry" => __MODULE__.Registry,
    "Capacity" => __MODULE__.Capacity,
    "Session.Supervisor" => __MODULE__.SessionSupervisor
  }

  defp unique_name(prefix), do: Map.fetch!(@process_names, prefix)

  defp ensure_symphony_http_bridge! do
    case HttpServer.bound_port() do
      port when is_integer(port) and port > 0 ->
        port

      _port ->
        port = free_port!()
        start_supervised!({HttpServer, host: "127.0.0.1", port: port})
        port
    end
  end

  defp put_dynamic_tool_source! do
    previous_source = Application.get_env(:symphony_elixir, :dynamic_tool_source)
    previous_owner = Application.get_env(:symphony_elixir, :worker_daemon_dynamic_tool_probe_owner)

    Application.put_env(:symphony_elixir, :dynamic_tool_source, DynamicToolSource)
    Application.put_env(:symphony_elixir, :worker_daemon_dynamic_tool_probe_owner, self())

    on_exit(fn ->
      restore_application_env(:dynamic_tool_source, previous_source)
      restore_application_env(:worker_daemon_dynamic_tool_probe_owner, previous_owner)
    end)
  end

  defp dynamic_tool_context do
    DynamicTool.capture_context(
      dynamic_tool_source: DynamicToolSource,
      dynamic_tool_probe_owner: self()
    )
  end

  defp empty_tool_context, do: %{"tool_specs" => [], "tool_metadata" => %{}, "tool_environment" => %{}}

  defp restore_application_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_application_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
