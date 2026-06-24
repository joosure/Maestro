defmodule SymphonyWorkerDaemon.ProviderAppServerTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.EventStreamSupervisor
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyWorkerDaemon.{Api, CapacityManager}
  alias SymphonyWorkerDaemon.Session

  @moduletag timeout: 60_000

  test "claude code app-server can run a turn through worker daemon executor" do
    workspace = tmp_dir!("claude-worker-daemon-turn")
    script = fake_claude_script!(workspace)
    port = free_port!()
    token = "provider-app-server-token"
    ledger = unique_name("Session.Ledger")
    registry = unique_name("Registry")
    capacity = unique_name("Capacity")
    supervisor = unique_name("Session.Supervisor")
    event_stream_supervisor = unique_name("EventStreamSupervisor")

    start_supervised!({Session.Ledger, name: ledger})
    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})
    start_supervised!({Session.Supervisor, name: supervisor, session_ledger: ledger})
    start_supervised!({EventStreamSupervisor, name: event_stream_supervisor})

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
            worker_id: "provider-app-worker",
            daemon_instance_id: "provider-app-daemon",
            allowed_executables: [script]
          ]},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: port}
    )

    config =
      ProviderConfig.new(%{
        kind: "claude_code",
        options: %{
          command_argv: [script],
          prompt_transport: "stream_json",
          permission_mode: "bypassPermissions",
          turn_timeout_ms: 10_000,
          read_timeout_ms: 5_000,
          stall_timeout_ms: 5_000
        }
      })

    assert :ok =
             AgentProvider.prepare_workspace(workspace,
               agent_provider_config: config,
               tool_context: empty_tool_context()
             )

    assert {:ok, session} =
             AgentProvider.start_session(workspace,
               agent_provider_config: config,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "provider-app",
               worker_daemon_endpoint: "http://127.0.0.1:#{port}",
               worker_daemon_token: token,
               worker_daemon_timeout_ms: 10_000,
               worker_daemon_event_stream_supervisor: event_stream_supervisor,
               tool_context: empty_tool_context(),
               dynamic_tool_exposure: :all,
               run_id: "provider-app-server-turn"
             )

    assert session.metadata.worker_daemon_worker_id == "provider-app-worker"
    assert session.metadata.worker_daemon_instance_id == "provider-app-daemon"

    assert {:ok, result} =
             AgentProvider.run_turn(
               session,
               "Reply with exactly worker-daemon-ok",
               %{id: "issue-provider-app", identifier: "WD-1", title: "Worker daemon provider turn"}
             )

    assert result.turn_id == "worker-daemon-turn"
    assert result.usage == %{input: 2, output: 3, reasoning: 4, total: 9}
    assert :ok = AgentProvider.stop_session(session)

    assert File.read!(Path.join(workspace, "provider_prompt.json")) =~ "worker-daemon-ok"
    assert File.read!(Path.join(workspace, "provider_args.txt")) =~ "--input-format stream-json"
  end

  defp fake_claude_script!(workspace) do
    script = Path.join(workspace, "fake_claude_code")

    File.write!(script, """
    #!/usr/bin/env bash
    set -eu

    printf '%s\\n' "$*" > provider_args.txt

    if IFS= read -r prompt_line; then
      printf '%s\\n' "$prompt_line" > provider_prompt.json
    fi

    printf '%s\\n' '{"type":"system","subtype":"init","session_id":"worker-daemon-session"}'
    printf '%s\\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"worker-daemon-ok"}],"usage":{"input_tokens":1,"output_tokens":1}}}'
    printf '%s\\n' '{"type":"result","subtype":"success","message":{"id":"worker-daemon-turn"},"usage":{"input_tokens":2,"output_tokens":3,"reasoning_tokens":4}}'
    """)

    File.chmod!(script, 0o755)
    script
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-worker-daemon-#{name}-#{System.unique_integer([:positive])}")
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
    "Session.Supervisor" => __MODULE__.SessionSupervisor,
    "EventStreamSupervisor" => __MODULE__.EventStreamSupervisor
  }

  defp unique_name(prefix), do: Map.fetch!(@process_names, prefix)

  defp empty_tool_context, do: %{"tool_specs" => [], "tool_metadata" => %{}, "tool_environment" => %{}}
end
