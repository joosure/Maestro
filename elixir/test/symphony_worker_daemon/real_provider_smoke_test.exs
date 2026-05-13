defmodule SymphonyWorkerDaemon.RealProviderSmokeTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Client
  alias SymphonyWorkerDaemon.{Api, CapacityManager}
  alias SymphonyWorkerDaemon.Session

  @moduletag :real_provider_smoke
  @moduletag timeout: 60_000

  @run_env "SYMPHONY_RUN_WORKER_DAEMON_PROVIDER_SMOKE"
  @claude_skip_reason if(System.get_env(@run_env) != "1",
                        do: "set #{@run_env}=1 to enable real provider CLI worker-daemon smoke tests",
                        else: if(System.find_executable("claude"), do: nil, else: "claude executable was not found in PATH")
                      )
  @codex_skip_reason if(System.get_env(@run_env) != "1",
                       do: "set #{@run_env}=1 to enable real provider CLI worker-daemon smoke tests",
                       else: if(System.find_executable("codex"), do: nil, else: "codex executable was not found in PATH")
                     )
  @opencode_skip_reason if(System.get_env(@run_env) != "1",
                          do: "set #{@run_env}=1 to enable real provider CLI worker-daemon smoke tests",
                          else: if(System.find_executable("opencode"), do: nil, else: "opencode executable was not found in PATH")
                        )

  @tag skip: @claude_skip_reason
  test "runs claude --version through the worker daemon" do
    run_provider_version_smoke!("claude", ["--version"])
  end

  @tag skip: @codex_skip_reason
  test "runs codex --version through the worker daemon" do
    run_provider_version_smoke!("codex", ["--version"])
  end

  @tag skip: @opencode_skip_reason
  test "runs opencode --version through the worker daemon" do
    run_provider_version_smoke!("opencode", ["--version"])
  end

  defp run_provider_version_smoke!(command_name, args) do
    command_path = System.find_executable(command_name) || flunk("#{command_name} executable was not found in PATH")
    workspace = tmp_dir!("real-provider-#{command_name}")
    port = free_port!()
    token = "provider-smoke-token"
    ledger = unique_name("Session.Ledger#{command_name}")
    registry = unique_name("Registry#{command_name}")
    capacity = unique_name("Capacity#{command_name}")
    supervisor = unique_name("Session.Supervisor#{command_name}")

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
            worker_id: "provider-smoke-worker",
            daemon_instance_id: "provider-smoke-daemon",
            allowed_executables: [command_path]
          ]},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: port}
    )

    target =
      Target.new(
        placement: :worker_daemon,
        worker_pool: "provider-smoke",
        workspace_path: workspace,
        metadata: %{
          worker_daemon_endpoint: "http://127.0.0.1:#{port}",
          run_id: "provider-smoke-#{command_name}",
          agent_provider_kind: command_name
        }
      )

    command_spec = CommandSpec.new(argv: [command_path | args], cwd: workspace)

    assert {:ok, handle} =
             Client.create_session(command_spec, target,
               worker_daemon_token: token,
               request_id: "provider-smoke-#{command_name}",
               worker_daemon_timeout_ms: 15_000
             )

    assert handle.worker_id == "provider-smoke-worker"
    assert handle.daemon_instance_id == "provider-smoke-daemon"

    assert_eventually(fn ->
      case Client.session_status(handle) do
        {:ok, "exited"} -> true
        {:ok, "failed"} -> flunk("#{command_name} --version exited with failure")
        _other -> false
      end
    end)

    events =
      assert_eventually(fn ->
        case Client.session_events(handle, after_event_id: 0, limit: 20) do
          {:ok, events} when events != [] -> {:ok, events}
          _other -> false
        end
      end)

    output = Enum.map_join(events, "\n", &Map.get(&1, :data, ""))
    assert output =~ ~r/\d+\.\d+|\w+/u

    assert :ok = Client.cleanup_session(handle)
  end

  defp assert_eventually(fun, attempts \\ 80)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    case fun.() do
      false ->
        Process.sleep(50)
        assert_eventually(fun, attempts - 1)

      nil ->
        Process.sleep(50)
        assert_eventually(fun, attempts - 1)

      true ->
        assert true

      {:ok, value} ->
        value

      value ->
        value
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition did not become true")

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
    "Session.Ledgerclaude" => __MODULE__.ClaudeSessionLedger,
    "Registryclaude" => __MODULE__.ClaudeRegistry,
    "Capacityclaude" => __MODULE__.ClaudeCapacity,
    "Session.Supervisorclaude" => __MODULE__.ClaudeSessionSupervisor,
    "Session.Ledgercodex" => __MODULE__.CodexSessionLedger,
    "Registrycodex" => __MODULE__.CodexRegistry,
    "Capacitycodex" => __MODULE__.CodexCapacity,
    "Session.Supervisorcodex" => __MODULE__.CodexSessionSupervisor,
    "Session.Ledgeropencode" => __MODULE__.OpenCodeSessionLedger,
    "Registryopencode" => __MODULE__.OpenCodeRegistry,
    "Capacityopencode" => __MODULE__.OpenCodeCapacity,
    "Session.Supervisoropencode" => __MODULE__.OpenCodeSessionSupervisor
  }

  defp unique_name(prefix), do: Map.fetch!(@process_names, prefix)
end
