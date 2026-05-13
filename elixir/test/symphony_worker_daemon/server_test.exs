defmodule SymphonyWorkerDaemon.ServerTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Client
  alias SymphonyElixir.Platform.Process, as: PlatformProcess
  alias SymphonyWorkerDaemon.{Api, CapacityManager, CommandPolicy, ProcessRunner, Protocol, RateLimiter, WorkspaceManager}
  alias SymphonyWorkerDaemon.Session

  defmodule CrashOnStopRunner do
    def start(_command, _cwd, _env, opts) do
      send(Keyword.fetch!(opts, :owner), {:provider_started, Keyword.fetch!(opts, :label)})
      {:ok, :fake_provider_handle}
    end

    def stop(_handle, _opts), do: raise("simulated provider stop crash")
  end

  defmodule PassiveRunner do
    def start(_command, _cwd, _env, opts) do
      owner = Keyword.fetch!(opts, :owner)
      send(owner, :passive_runner_started)
      {:ok, {:passive_runner, owner}}
    end

    def stop({:passive_runner, owner}, opts) do
      send(owner, {:passive_runner_stopped, opts})
      :ok
    end
  end

  defmodule CountingCapacityManager do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def releases(server), do: GenServer.call(server, :releases)

    @impl true
    def init(opts), do: {:ok, %{owner: Keyword.fetch!(opts, :owner), releases: []}}

    @impl true
    def handle_call({:admit, attrs}, _from, state) do
      send(state.owner, {:capacity_admitted, attrs})
      {:reply, {:ok, "lease-counted"}, state}
    end

    def handle_call({:release, lease_id}, _from, state) do
      send(state.owner, {:capacity_released, lease_id})
      {:reply, :ok, %{state | releases: [lease_id | state.releases]}}
    end

    def handle_call(:releases, _from, state) do
      {:reply, Enum.reverse(state.releases), state}
    end
  end

  test "capacity manager admits, rejects when full, and releases leases" do
    capacity = unique_name("Capacity")
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})

    assert {:ok, lease_id} = CapacityManager.admit(capacity, %{session_id: "session-1"})
    assert %{status: :full, active_sessions: 1, max_sessions: 1} = CapacityManager.status(capacity)
    assert {:error, :worker_full} = CapacityManager.admit(capacity, %{session_id: "session-2"})

    assert :ok = CapacityManager.release(capacity, lease_id)
    assert %{status: :ready, active_sessions: 0} = CapacityManager.status(capacity)
  end

  test "session cleanup releases capacity once across stop and terminate paths" do
    %{registry: registry, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    capacity = start_supervised!({CountingCapacityManager, owner: self()})
    workspace = tmp_dir!("session-release-once")

    request =
      session_request(workspace, ["fake-provider"],
        request_id: "request-release-once",
        session_id: "session-release-once"
      )

    assert {:ok, pid, %{"session_id" => "session-release-once", "status" => "running", "lease_id" => "lease-counted"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allow_any_executable?: true,
               process_runner: PassiveRunner,
               process_runner_opts: [owner: self()]
             )

    assert_receive {:capacity_admitted, %{session_id: "session-release-once"}}
    assert_receive :passive_runner_started

    assert :ok = Session.Server.cleanup(pid)
    assert_receive {:passive_runner_stopped, _opts}
    assert_receive {:capacity_released, "lease-counted"}
    refute_receive {:capacity_released, "lease-counted"}, 100
    assert CountingCapacityManager.releases(capacity) == ["lease-counted"]
  end

  test "capacity manager enforces per-tenant concurrent session quota" do
    capacity = unique_name("TenantCapacity")
    start_supervised!({CapacityManager, name: capacity, max_sessions: 3, max_sessions_per_tenant: 1})

    assert {:ok, owner_a_lease} =
             CapacityManager.admit(capacity, %{
               session_id: "session-owner-a-1",
               caller: %{"owner" => "owner-a", "tenant_id" => "tenant-a"}
             })

    assert {:error, :tenant_session_quota_exceeded} =
             CapacityManager.admit(capacity, %{
               session_id: "session-owner-a-2",
               caller: %{"owner" => "owner-a", "tenant_id" => "tenant-a"}
             })

    assert {:ok, owner_b_lease} =
             CapacityManager.admit(capacity, %{
               session_id: "session-owner-b-1",
               caller: %{"owner" => "owner-b", "tenant_id" => "tenant-b"}
             })

    assert %{status: :ready, active_sessions: 2, active_tenants: 2, max_sessions_per_tenant: 1} = CapacityManager.status(capacity)

    assert :ok = CapacityManager.release(capacity, owner_a_lease)
    assert :ok = CapacityManager.release(capacity, owner_b_lease)
  end

  test "workspace manager validates canonical workspace boundaries" do
    root = tmp_dir!("workspace-root")
    workspace = Path.join(root, "issue-1")
    File.mkdir_p!(workspace)
    {:ok, canonical_workspace} = SymphonyElixir.PathSafety.canonicalize(workspace)
    {:ok, canonical_root} = SymphonyElixir.PathSafety.canonicalize(root)

    assert {:ok, ^canonical_workspace} =
             WorkspaceManager.validate_workspace(%{"cwd" => workspace}, workspace_roots: [root])

    outside = tmp_dir!("workspace-outside")
    {:ok, canonical_outside} = SymphonyElixir.PathSafety.canonicalize(outside)

    assert {:error, {:workspace_outside_allowed_roots, ^canonical_outside, [^canonical_root]}} =
             WorkspaceManager.validate_workspace(%{"cwd" => outside}, workspace_roots: [root])
  end

  test "workspace manager refuses to delete an allowed workspace root" do
    root = tmp_dir!("workspace-cleanup-root")
    workspace = Path.join(root, "issue-1")
    File.mkdir_p!(workspace)
    {:ok, canonical_root} = SymphonyElixir.PathSafety.canonicalize(root)

    assert {:error, {:workspace_cleanup_refuses_root, ^canonical_root}} =
             WorkspaceManager.cleanup_workspace(root, workspace_roots: [root], delete_workspace?: true)

    assert File.dir?(root)

    assert :ok =
             WorkspaceManager.cleanup_workspace(workspace, workspace_roots: [root], delete_workspace?: true)

    refute File.exists?(workspace)
    assert File.dir?(root)
  end

  test "process runner disables shell command mode by default" do
    root = tmp_dir!("process-runner")

    assert {:error, :shell_command_disabled} =
             ProcessRunner.start(%{"mode" => "shell", "command" => "echo unsafe"}, root, %{})
  end

  test "command policy requires the resolved executable path to match the allowlist" do
    workspace = tmp_dir!("command-policy-path")
    allowed = executable_file!(Path.join(workspace, "allowed/tool"))
    same_name_different_path = executable_file!(Path.join(workspace, "other/tool"))

    assert :ok =
             CommandPolicy.validate(%{"mode" => "argv", "argv" => [allowed, "--version"]}, workspace, allowed_executables: [allowed])

    assert {:error, {:command_not_allowlisted, %{command: ^same_name_different_path, name: "tool"}}} =
             CommandPolicy.validate(%{"mode" => "argv", "argv" => [same_name_different_path, "--version"]}, workspace, allowed_executables: [allowed])
  end

  test "session server child spec is temporary to avoid replaying provider execution after crashes" do
    assert %{restart: :temporary} =
             Session.Server.child_spec(
               session_id: "session-child-spec",
               request: session_request(tmp_dir!("child-spec"), ["/bin/echo", "ok"])
             )
  end

  test "session server crash marks session lost and does not replay provider execution" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    ledger = unique_name("SessionLedgerNoRestart")
    workspace = tmp_dir!("session-no-restart")

    start_supervised!({Session.Ledger, name: ledger})

    request =
      session_request(workspace, ["fake-provider"],
        request_id: "request-no-restart",
        session_id: "session-no-restart",
        run_id: "run-no-restart"
      )

    assert {:ok, pid, %{"status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               session_ledger: ledger,
               workspace_roots: [workspace],
               allow_any_executable?: true,
               process_runner: CrashOnStopRunner,
               process_runner_opts: [owner: self(), label: :no_restart]
             )

    assert_receive {:provider_started, :no_restart}
    ref = Process.monitor(pid)

    catch_exit(Session.Server.stop_session(pid))

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    assert_eventually(fn -> Session.Server.lookup(registry, "session-no-restart") == {:error, :session_not_found} end)
    refute_receive {:provider_started, :no_restart}, 100
    assert %{status: :ready, active_sessions: 0} = CapacityManager.status(capacity)

    assert_eventually(fn ->
      case Session.Ledger.get_session(ledger, "session-no-restart") do
        {:ok, %{"status" => "lost", "lost_reason" => "session_server_terminated"}} -> true
        _other -> false
      end
    end)
  end

  test "session supervisor starts provider-neutral child process and cleans it up" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("session")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    request = session_request(workspace, [elixir, "-e", "IO.puts(\"ready TOKEN=secret-value\"); Process.sleep(:infinity)"])

    assert {:ok, pid, %{"session_id" => "session-1", "status" => "running", "lease_id" => lease_id}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir]
             )

    assert is_binary(lease_id)
    assert %{status: :full, active_sessions: 1} = CapacityManager.status(capacity)
    assert {:ok, ^pid} = Session.Server.lookup(registry, "session-1")
    assert Session.Server.status(pid)["os_pid"] |> is_integer()

    assert_eventually(fn ->
      events = Session.Server.events(pid)
      Enum.any?(events, &(Map.get(&1, "type") == "output" and String.contains?(Map.get(&1, "data", ""), "ready")))
    end)

    events = Session.Server.events(pid)
    assert [%{"event_id" => event_id} | _rest] = events
    assert is_integer(event_id)
    refute inspect(events) =~ "secret-value"
    assert inspect(events) =~ "[REDACTED]"

    assert :ok = Session.Server.cleanup(pid)
    assert_eventually(fn -> Session.Server.lookup(registry, "session-1") == {:error, :session_not_found} end)
    assert %{status: :ready, active_sessions: 0} = CapacityManager.status(capacity)
  end

  test "session server enforces session timeout policy" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("session-timeout")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    request =
      workspace
      |> session_request([elixir, "-e", "Process.sleep(:infinity)"], request_id: "request-timeout", session_id: "session-timeout")
      |> Map.put("timeout_policy", %{"session_timeout_ms" => 50})

    assert {:ok, pid, %{"session_id" => "session-timeout", "status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir]
             )

    assert_eventually(fn ->
      case Session.Server.status(pid) do
        %{"status" => "failed", "stop_reason" => "session_timeout"} -> true
        _status -> false
      end
    end)

    assert %{status: :ready, active_sessions: 0} = CapacityManager.status(capacity)
  end

  test "session server enforces startup timeout policy" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("startup-timeout")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    request =
      workspace
      |> session_request([elixir, "-e", "Process.sleep(:infinity)"], request_id: "request-startup-timeout", session_id: "session-startup-timeout")
      |> Map.put("timeout_policy", %{"startup_timeout_ms" => 50})

    assert {:ok, pid, %{"session_id" => "session-startup-timeout", "status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir]
             )

    assert_eventually(fn ->
      case Session.Server.status(pid) do
        %{"status" => "failed", "stop_reason" => "startup_timeout"} -> true
        _status -> false
      end
    end)

    assert %{status: :ready, active_sessions: 0} = CapacityManager.status(capacity)
  end

  test "session server enforces idle timeout after provider output" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("idle-timeout")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    request =
      workspace
      |> session_request([elixir, "-e", "IO.puts(\"ready\"); Process.sleep(:infinity)"], request_id: "request-idle-timeout", session_id: "session-idle-timeout")
      |> Map.put("timeout_policy", %{"startup_timeout_ms" => 1_000, "idle_timeout_ms" => 50})

    assert {:ok, pid, %{"session_id" => "session-idle-timeout", "status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir]
             )

    assert_eventually(fn ->
      Session.Server.events(pid)
      |> Enum.any?(&(Map.get(&1, "type") == "output" and String.contains?(Map.get(&1, "data", ""), "ready")))
    end)

    assert_eventually(fn ->
      case Session.Server.status(pid) do
        %{"status" => "failed", "stop_reason" => "idle_timeout"} -> true
        _status -> false
      end
    end)

    assert %{status: :ready, active_sessions: 0} = CapacityManager.status(capacity)
  end

  test "session server applies request output buffer resource budget" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("output-budget")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    request =
      workspace
      |> session_request([elixir, "-e", "IO.write(String.duplicate(\"x\", 16))"], request_id: "request-output-budget", session_id: "session-output-budget")
      |> Map.put("resource_budget", %{"output_buffer_bytes" => 4})

    assert {:ok, pid, %{"session_id" => "session-output-budget", "status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir],
               output_buffer_limit: 1_024
             )

    status =
      assert_eventually(fn ->
        case Session.Server.status(pid) do
          %{"output_truncated" => true, "output_bytes" => output_bytes} = status when output_bytes >= 16 -> {:ok, status}
          _status -> false
        end
      end)

    assert status["output_truncated"] == true
    assert Enum.any?(Session.Server.events(pid), &(Map.get(&1, "type") == "output_truncated"))

    assert %{status: :ready, active_sessions: 0} =
             assert_eventually(fn ->
               case CapacityManager.status(capacity) do
                 %{status: :ready, active_sessions: 0} = status -> {:ok, status}
                 _status -> false
               end
             end)
  end

  test "session supervisor treats duplicate creates as idempotent and rejects conflicting reuse" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("session-duplicate")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    request = session_request(workspace, [elixir, "-e", "Process.sleep(:infinity)"], request_id: "request-duplicate", session_id: "session-duplicate")

    assert {:ok, pid, %{"session_id" => "session-duplicate", "status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir]
             )

    assert {:ok, ^pid, %{"session_id" => "session-duplicate", "status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir]
             )

    conflicting_request = %{request | "command" => %{"mode" => "argv", "argv" => [elixir, "-e", "IO.puts(\"different\")"]}}

    assert {:error, {:session_conflict, "session-duplicate"}} =
             Session.Supervisor.start_session(supervisor, conflicting_request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allowed_executables: [elixir]
             )

    assert %{status: :full, active_sessions: 1} = CapacityManager.status(capacity)
    assert :ok = Session.Server.cleanup(pid)
  end

  test "HTTP API authenticates, creates, inspects, stops, and cleans sessions" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 2)
    workspace = tmp_dir!("api-session")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      worker_id: "worker-1",
      daemon_instance_id: "daemon-1",
      allowed_executables: [elixir]
    ]

    unauthorized =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(session_request(workspace, [elixir, "-e", "IO.puts(\"ready TOKEN=secret-value\"); Process.sleep(:infinity)"])))
      |> put_req_header("content-type", "application/json")
      |> Api.call(opts)

    assert unauthorized.status == 401

    create_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(session_request(workspace, [elixir, "-e", "IO.puts(\"ready TOKEN=secret-value\"); Process.sleep(:infinity)"])))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert create_conn.status == 201
    create_body = Jason.decode!(create_conn.resp_body)
    assert create_body["session_id"] == "session-1"
    assert create_body["worker_id"] == "worker-1"
    assert create_body["daemon_instance_id"] == "daemon-1"

    list_conn =
      :get
      |> conn("/api/v1/worker-daemon/sessions?owner=symphony&run_id=run-1")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert list_conn.status == 200
    assert [%{"session_id" => "session-1", "status" => "running", "owner" => "symphony", "run_id" => "run-1"}] = Jason.decode!(list_conn.resp_body)["sessions"]

    status_conn =
      :get
      |> conn("/api/v1/worker-daemon/sessions/session-1")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert status_conn.status == 200
    assert Jason.decode!(status_conn.resp_body)["status"] == "running"

    events_body =
      assert_eventually(fn ->
        events_conn =
          :get
          |> conn("/api/v1/worker-daemon/sessions/session-1/events?after_event_id=0&limit=10")
          |> put_req_header("authorization", "Bearer daemon-token")
          |> Api.call(opts)

        events = Jason.decode!(events_conn.resp_body)["events"] || []

        if events_conn.status == 200 and Enum.any?(events, &(Map.get(&1, "type") == "output")) do
          {:ok, events}
        else
          false
        end
      end)

    assert [%{"event_id" => first_event_id} | _rest] = events_body
    assert is_integer(first_event_id)
    refute inspect(events_body) =~ "secret-value"
    assert inspect(events_body) =~ "[REDACTED]"

    stop_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions/session-1/stop", Jason.encode!(Protocol.stop_request(request_id: "request-stop-1", reason: "operator_stop")))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert stop_conn.status == 200
    assert Jason.decode!(stop_conn.resp_body)["status"] == "stopped"

    stopped_status_conn =
      :get
      |> conn("/api/v1/worker-daemon/sessions/session-1")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert stopped_status_conn.status == 200
    assert Jason.decode!(stopped_status_conn.resp_body)["stop_reason"] == "operator_stop"

    cleanup_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions/session-1/cleanup", Jason.encode!(Protocol.cleanup_request(request_id: "request-cleanup-1")))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert cleanup_conn.status == 200
    assert Jason.decode!(cleanup_conn.resp_body)["status"] == "cleaned"
  end

  test "HTTP API fails closed unless unauthenticated mode is explicit" do
    unauthenticated =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> Api.call([])

    assert unauthenticated.status == 401

    allowed =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> Api.call(allow_unauthenticated?: true)

    assert allowed.status == 200
  end

  test "HTTP API exposes source availability metadata" do
    with_env(
      %{
        "MAESTRO_SOURCE_URL" => "https://example.com/worker/source",
        "MAESTRO_SOURCE_REVISION" => "worker-rev"
      },
      fn ->
        response =
          :get
          |> conn("/api/v1/worker-daemon/source")
          |> put_req_header("authorization", "Bearer daemon-token")
          |> Api.call(token: "daemon-token")

        assert response.status == 200

        assert Jason.decode!(response.resp_body) == %{
                 "license" => "AGPL-3.0-only",
                 "source_url" => "https://example.com/worker/source",
                 "source_revision" => "worker-rev",
                 "notice_path" => "/api/v1/worker-daemon/source",
                 "inherited_license_file" => "LICENSES/Apache-2.0.txt",
                 "modification_notice_file" => "MODIFICATIONS.md",
                 "source_guidance_file" => "SOURCE.md",
                 "third_party_license_file" => "THIRD_PARTY_LICENSES.md"
               }
      end
    )
  end

  test "HTTP API throttles failed-auth and authenticated tenant request bursts" do
    auth_limiter = unique_name("AuthRateLimiter")
    start_supervised!({RateLimiter, name: auth_limiter})

    auth_opts = [
      token: "daemon-token",
      rate_limiter: auth_limiter,
      unauthenticated_rate_limit: 1,
      rate_limit_window_ms: 1_000
    ]

    first_auth_failure =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> Api.call(auth_opts)

    second_auth_failure =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> Api.call(auth_opts)

    assert first_auth_failure.status == 401
    assert second_auth_failure.status == 429
    assert get_resp_header(second_auth_failure, "retry-after") == ["1"]
    assert Jason.decode!(second_auth_failure.resp_body)["code"] == "rate_limited"

    api_limiter = unique_name("ApiRateLimiter")
    start_supervised!({RateLimiter, name: api_limiter})

    api_opts = [
      token: "daemon-token",
      rate_limiter: api_limiter,
      api_rate_limit: 1,
      rate_limit_window_ms: 1_000
    ]

    first_request =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(api_opts)

    second_request =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(api_opts)

    assert first_request.status == 200
    assert second_request.status == 429
    assert Jason.decode!(second_request.resp_body)["code"] == "rate_limited"
  end

  test "HTTP API rejects mutating requests without protocol version" do
    opts = [token: "daemon-token", registry: unique_name("MissingRegistry")]

    stop_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions/session-missing/stop", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert stop_conn.status == 422
    assert Jason.decode!(stop_conn.resp_body)["code"] == "protocol_version_missing"
  end

  test "HTTP API rejects oversized declared request bodies and create payload fields" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("api-payload-limits")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      allowed_executables: [elixir],
      max_protocol_env_bytes: 4
    ]

    oversized_body_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions", "{}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", Integer.to_string(1_048_577))
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert oversized_body_conn.status == 413
    assert Jason.decode!(oversized_body_conn.resp_body)["code"] == "payload_too_large"

    oversized_env_request =
      workspace
      |> session_request([elixir, "-e", "IO.puts(\"ok\")"], request_id: "request-env-too-large", session_id: "session-env-too-large")
      |> Map.put("env", %{"TOKEN" => "secret-value"})

    oversized_env_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(oversized_env_request))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert oversized_env_conn.status == 413
    assert Jason.decode!(oversized_env_conn.resp_body)["code"] == "payload_too_large"
  end

  test "HTTP API throttles per-tenant session create bursts before admission" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 2)
    limiter = unique_name("CreateRateLimiter")
    start_supervised!({RateLimiter, name: limiter})

    workspace = tmp_dir!("api-create-rate-limit")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      rate_limiter: limiter,
      api_rate_limit: 100,
      session_create_rate_limit: 1,
      rate_limit_window_ms: 1_000,
      workspace_roots: [workspace],
      allowed_executables: [elixir]
    ]

    first_create =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(session_request(workspace, [elixir, "-e", "Process.sleep(:infinity)"])))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    second_create =
      :post
      |> conn(
        "/api/v1/worker-daemon/sessions",
        Jason.encode!(session_request(workspace, [elixir, "-e", "Process.sleep(:infinity)"], request_id: "request-create-rate-2", session_id: "session-create-rate-2"))
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert first_create.status == 201
    assert second_create.status == 429
    assert Jason.decode!(second_create.resp_body)["code"] == "rate_limited"
    assert %{active_sessions: 1} = CapacityManager.status(capacity)

    assert {:ok, pid} = Session.Supervisor.lookup(registry, "session-1")
    assert :ok = Session.Server.cleanup(pid)
  end

  test "HTTP API rejects unknown protocol fields before session mutation" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("api-strict-schema")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      allowed_executables: [elixir]
    ]

    unknown_create =
      workspace
      |> session_request([elixir, "-e", "IO.puts(\"ok\")"], request_id: "request-unknown-create", session_id: "session-unknown-create")
      |> Map.put("unexpected", true)

    create_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(unknown_create))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert create_conn.status == 422
    assert Jason.decode!(create_conn.resp_body)["code"] == "payload_unknown_fields"

    unknown_budget =
      workspace
      |> session_request([elixir, "-e", "IO.puts(\"ok\")"], request_id: "request-unknown-budget", session_id: "session-unknown-budget")
      |> Map.put("resource_budget", %{"cpu_ms" => 10})

    budget_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(unknown_budget))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert budget_conn.status == 422
    assert Jason.decode!(budget_conn.resp_body)["code"] == "payload_unknown_fields"

    input_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions/session-missing/input", Jason.encode!(Protocol.input_request("hello", request_id: "request-input") |> Map.put("extra", "nope")))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert input_conn.status == 422
    assert Jason.decode!(input_conn.resp_body)["code"] == "payload_unknown_fields"
  end

  test "HTTP API redacts sensitive values from unexpected start errors" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("api-error-redaction")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      allowed_executables: [elixir]
    ]

    rejected =
      :post
      |> conn(
        "/api/v1/worker-daemon/sessions",
        Jason.encode!(session_request(workspace, ["TOKEN=secret-value"], request_id: "request-redacted", session_id: "session-redacted"))
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    body = Jason.decode!(rejected.resp_body)

    assert rejected.status == 422
    assert body["code"] == "session_start_failed"
    refute rejected.resp_body =~ "secret-value"
    assert body["details"] =~ "[REDACTED]"
  end

  test "HTTP API enforces owner and tenant authorization for session operations" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 2)
    workspace = tmp_dir!("api-session-authz")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      api_clients: [
        %{token: "token-a", owner: "owner-a", tenant_id: "tenant-a"},
        %{token: "token-b", owner: "owner-b", tenant_id: "tenant-b"}
      ],
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      worker_id: "worker-1",
      daemon_instance_id: "daemon-1",
      allowed_executables: [elixir]
    ]

    create_conn =
      :post
      |> conn(
        "/api/v1/worker-daemon/sessions",
        Jason.encode!(
          session_request(workspace, [elixir, "-e", "Process.sleep(:infinity)"],
            request_id: "request-owner-a",
            session_id: "session-owner-a",
            run_id: "run-owner-a",
            owner: "owner-a",
            tenant_id: "tenant-a"
          )
        )
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer token-a")
      |> Api.call(opts)

    assert create_conn.status == 201

    mismatch_create_conn =
      :post
      |> conn(
        "/api/v1/worker-daemon/sessions",
        Jason.encode!(
          session_request(workspace, [elixir, "-e", "Process.sleep(:infinity)"],
            request_id: "request-mismatch",
            session_id: "session-mismatch",
            run_id: "run-mismatch",
            owner: "owner-a",
            tenant_id: "tenant-a"
          )
        )
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer token-b")
      |> Api.call(opts)

    assert mismatch_create_conn.status == 403

    list_forbidden_conn =
      :get
      |> conn("/api/v1/worker-daemon/sessions?owner=owner-a&tenant_id=tenant-a")
      |> put_req_header("authorization", "Bearer token-b")
      |> Api.call(opts)

    assert list_forbidden_conn.status == 403

    own_list_conn =
      :get
      |> conn("/api/v1/worker-daemon/sessions")
      |> put_req_header("authorization", "Bearer token-b")
      |> Api.call(opts)

    assert own_list_conn.status == 200
    assert Jason.decode!(own_list_conn.resp_body)["sessions"] == []

    for {method, path, body} <- [
          {:get, "/api/v1/worker-daemon/sessions/session-owner-a", nil},
          {:get, "/api/v1/worker-daemon/sessions/session-owner-a/events", nil},
          {:post, "/api/v1/worker-daemon/sessions/session-owner-a/input", Jason.encode!(Protocol.input_request("hello\n", request_id: "request-input-forbidden"))},
          {:post, "/api/v1/worker-daemon/sessions/session-owner-a/stop", Jason.encode!(Protocol.stop_request(request_id: "request-stop-forbidden"))},
          {:post, "/api/v1/worker-daemon/sessions/session-owner-a/cleanup", Jason.encode!(Protocol.cleanup_request(request_id: "request-cleanup-forbidden"))}
        ] do
      conn =
        method
        |> conn(path, body)
        |> put_req_header("authorization", "Bearer token-b")
        |> maybe_put_json_content_type(body)
        |> Api.call(opts)

      assert conn.status == 403
    end

    cleanup_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions/session-owner-a/cleanup", Jason.encode!(Protocol.cleanup_request(request_id: "request-owner-cleanup")))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer token-a")
      |> Api.call(opts)

    assert cleanup_conn.status == 200
  end

  test "session ledger persists active sessions as lost after daemon restart" do
    path = Path.join(tmp_dir!("session-ledger"), "sessions.json")
    ledger = unique_name("Session.Ledger")

    start_supervised!({Session.Ledger, name: ledger, path: path})
    :ok = Session.Ledger.record_session(ledger, %{"session_id" => "session-lost-1", "status" => "running", "owner" => "symphony", "run_id" => "run-lost"})

    assert_eventually(fn ->
      Session.Ledger.get_session(ledger, "session-lost-1") == {:ok, %{"session_id" => "session-lost-1", "status" => "running", "owner" => "symphony", "run_id" => "run-lost"}}
    end)

    stop_supervised!(Session.Ledger)

    restarted_ledger = unique_name("SessionLedgerRestarted")
    start_supervised!({Session.Ledger, name: restarted_ledger, path: path})

    assert {:ok, %{"status" => "lost", "lost_reason" => "daemon_restarted"}} =
             Session.Ledger.get_session(restarted_ledger, "session-lost-1")
  end

  test "application startup sweeps ledger-backed orphan OS processes" do
    workspace = tmp_dir!("orphan-sweep")
    ledger_path = Path.join(tmp_dir!("orphan-ledger"), "sessions.json")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    assert {:ok, port} =
             PlatformProcess.start_argv(
               [
                 elixir,
                 "-e",
                 "IO.puts(\"orphan-ready\"); Process.sleep(:infinity)"
               ],
               cwd: workspace,
               line: 1024
             )

    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "orphan-ready"}}}, 5_000
    assert PlatformProcess.os_process_alive?(os_pid)

    ledger = unique_name("OrphanSweepLedger")
    start_supervised!({Session.Ledger, name: ledger, path: ledger_path})

    :ok =
      Session.Ledger.record_session_sync(ledger, %{
        "session_id" => "session-orphan-sweep",
        "status" => "running",
        "owner" => "symphony",
        "run_id" => "run-orphan-sweep",
        "cwd" => workspace,
        "os_pid" => os_pid,
        "started_at_ms" => System.system_time(:millisecond),
        "updated_at_ms" => System.system_time(:millisecond)
      })

    stop_supervised!(Session.Ledger)

    registry = unique_name("OrphanSweepRegistry")
    capacity = unique_name("OrphanSweepCapacity")
    session_supervisor = unique_name("OrphanSweepSessionSupervisor")
    app_supervisor = unique_name("OrphanSweepApplication")

    start_supervised!(
      {SymphonyWorkerDaemon.Application,
       name: app_supervisor,
       registry: registry,
       capacity_manager: capacity,
       session_ledger: ledger,
       session_ledger_path: ledger_path,
       session_supervisor: session_supervisor,
       workspace_roots: [workspace],
       orphan_sweep_grace_ms: 50,
       orphan_sweep_kill_wait_ms: 1_000,
       orphan_sweep_poll_ms: 25}
    )

    assert_eventually(fn -> not PlatformProcess.os_process_alive?(os_pid) end)

    assert {:ok,
            %{
              "status" => "lost",
              "lost_reason" => "daemon_restarted",
              "orphan_sweep_status" => "terminated",
              "orphan_sweep_os_pid" => ^os_pid,
              "orphan_sweep_alive_after" => false
            }} =
             assert_eventually(fn ->
               case Session.Ledger.get_session(ledger, "session-orphan-sweep") do
                 {:ok, %{"orphan_sweep_status" => "terminated"} = session} -> {:ok, {:ok, session}}
                 _session -> false
               end
             end)

    assert :ok = PlatformProcess.close_port(port)
  end

  test "HTTP API exposes lost ledger sessions and allows idempotent cleanup" do
    path = Path.join(tmp_dir!("api-session-ledger"), "sessions.json")
    ledger = unique_name("SessionLedgerApi")

    start_supervised!({Session.Ledger, name: ledger, path: path})

    :ok =
      Session.Ledger.record_session(ledger, %{
        "session_id" => "session-lost-api",
        "status" => "running",
        "owner" => "symphony",
        "run_id" => "run-lost-api",
        "updated_at_ms" => System.system_time(:millisecond)
      })

    assert_eventually(fn ->
      case Session.Ledger.get_session(ledger, "session-lost-api") do
        {:ok, %{"status" => "running"}} -> true
        _other -> false
      end
    end)

    stop_supervised!(Session.Ledger)

    restarted_ledger = unique_name("SessionLedgerApiRestarted")
    start_supervised!({Session.Ledger, name: restarted_ledger, path: path})

    opts = [
      token: "daemon-token",
      session_ledger: restarted_ledger,
      registry: unique_name("MissingRegistry")
    ]

    status_conn =
      :get
      |> conn("/api/v1/worker-daemon/sessions/session-lost-api")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert status_conn.status == 200
    assert Jason.decode!(status_conn.resp_body)["status"] == "lost"

    list_conn =
      :get
      |> conn("/api/v1/worker-daemon/sessions?owner=symphony&run_id=run-lost-api")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert list_conn.status == 200
    assert [%{"session_id" => "session-lost-api", "status" => "lost"}] = Jason.decode!(list_conn.resp_body)["sessions"]

    cleanup_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions/session-lost-api/cleanup", Jason.encode!(Protocol.cleanup_request(request_id: "request-lost-cleanup")))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert cleanup_conn.status == 200
    assert {:ok, %{"status" => "cleaned"}} = Session.Ledger.get_session(restarted_ledger, "session-lost-api")
  end

  test "HTTP API health reports protocol, capacity, and supported features" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 2)
    workspace = tmp_dir!("api-health")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      worker_id: "worker-1",
      daemon_instance_id: "daemon-1",
      allowed_executables: [elixir]
    ]

    health_conn =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert health_conn.status == 200
    body = Jason.decode!(health_conn.resp_body)
    assert body["status"] == "ready"
    assert body["protocol_version"] == Protocol.protocol_version()
    assert body["daemon_version"] == Protocol.daemon_version()
    assert body["worker_id"] == "worker-1"
    assert body["worker_profile_version"] == "default"
    assert "session_list" in body["features"]
    assert "executable_policy" in body["features"]
    refute "dynamic_tool_bridge_proxy" in body["features"]
    assert body["capacity"]["max_sessions"] == 2
    assert body["session_ledger"]["status"] == "ready"
    assert body["session_ledger"]["persistence"] == "disabled"
    assert [%{"kind" => "executable", "available" => true} | _rest] = body["capabilities"]

    enabled_bridge_conn =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(
        opts ++
          [
            enable_dynamic_tool_bridge_proxy?: true,
            allowed_dynamic_tool_bridge_upstreams: ["https://tools.example.com/api/v1/agent-tools/dynamic"]
          ]
      )

    assert enabled_bridge_conn.status == 200
    assert "dynamic_tool_bridge_proxy" in Jason.decode!(enabled_bridge_conn.resp_body)["features"]
  end

  test "HTTP API health reports degraded session ledger persistence" do
    capacity = unique_name("LedgerHealthCapacity")
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})

    root = tmp_dir!("ledger-health")
    blocker = Path.join(root, "not-a-directory")
    File.write!(blocker, "blocks ledger parent")
    ledger_path = Path.join(blocker, "sessions.json")
    ledger = unique_name("LedgerHealth")

    start_supervised!({Session.Ledger, name: ledger, path: ledger_path})

    health_conn =
      :get
      |> conn("/api/v1/worker-daemon/health")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(token: "daemon-token", capacity_manager: capacity, session_ledger: ledger)

    assert health_conn.status == 200
    body = Jason.decode!(health_conn.resp_body)
    assert body["status"] == "degraded"
    assert body["session_ledger"]["status"] == "degraded"
    assert body["session_ledger"]["last_error"]["operation"] == "load"
  end

  test "HTTP API rejects non-allowlisted commands before process start" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("api-command-policy")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      worker_id: "worker-1",
      daemon_instance_id: "daemon-1",
      allowed_executables: [elixir]
    ]

    rejected =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(session_request(workspace, ["/bin/echo", "unsafe"])))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert rejected.status == 422
    assert Jason.decode!(rejected.resp_body)["code"] == "command_rejected"
    assert %{status: :ready, active_sessions: 0} = CapacityManager.status(capacity)
  end

  test "Symphony worker daemon client talks to HTTP daemon end to end" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 2)
    workspace = tmp_dir!("http-e2e")
    port = free_port!()
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    start_supervised!(
      {Bandit,
       plug:
         {Api,
          [
            token: "daemon-token",
            registry: registry,
            capacity_manager: capacity,
            session_supervisor: supervisor,
            workspace_roots: [workspace],
            worker_id: "worker-http",
            daemon_instance_id: "daemon-http",
            allowed_executables: [elixir]
          ]},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: port}
    )

    target =
      Target.new(
        placement: :worker_daemon,
        worker_pool: "coding-linux",
        workspace_path: workspace,
        metadata: %{
          worker_daemon_endpoint: "http://127.0.0.1:#{port}",
          run_id: "run-http",
          agent_provider_kind: "fake"
        }
      )

    command_spec =
      CommandSpec.new(
        argv: [
          elixir,
          "-e",
          "line = IO.read(:line); IO.puts(\"got TOKEN=secret-value\"); System.halt(if(line == \"hello\\n\", do: 0, else: 2))"
        ],
        cwd: workspace
      )

    assert {:ok, handle} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               request_id: "request-http"
             )

    assert handle.session_id == "session-request-http"
    assert handle.worker_id == "worker-http"
    assert handle.daemon_instance_id == "daemon-http"
    assert {:ok, "running"} = Client.session_status(handle)

    assert {:ok, session_pid} = Session.Supervisor.lookup(registry, handle.session_id)
    assert :ok = Client.send_input(handle, "hello\n")

    assert_eventually(fn -> Session.Server.status(session_pid)["status"] == "exited" end)
    assert Session.Server.status(session_pid)["exit_status"] == 0

    events =
      assert_eventually(fn ->
        case Client.session_events(handle, after_event_id: 0, limit: 10) do
          {:ok, events} when events != [] -> {:ok, events}
          _other -> false
        end
      end)

    assert Enum.any?(events, &(&1.type == "output" and String.contains?(&1.data, "got")))
    refute inspect(events) =~ "secret-value"
    assert inspect(events) =~ "[REDACTED]"

    assert {:ok, [summary]} =
             Client.list_sessions(target,
               worker_daemon_token: "daemon-token"
             )

    assert summary.session_id == handle.session_id
    assert summary.run_id == "run-http"
    assert summary.owner == "symphony"

    assert :ok = Client.stop_session(handle)
    assert :ok = Client.cleanup_session(handle)

    assert_eventually(fn -> Session.Supervisor.lookup(registry, handle.session_id) == {:error, :session_not_found} end)
  end

  test "HTTP API returns stable retryable backpressure code when worker is full" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!(max_sessions: 1)
    workspace = tmp_dir!("api-worker-full")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    opts = [
      token: "daemon-token",
      registry: registry,
      capacity_manager: capacity,
      session_supervisor: supervisor,
      workspace_roots: [workspace],
      allowed_executables: [elixir]
    ]

    create_conn =
      :post
      |> conn("/api/v1/worker-daemon/sessions", Jason.encode!(session_request(workspace, [elixir, "-e", "Process.sleep(:infinity)"])))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert create_conn.status == 201

    worker_full_conn =
      :post
      |> conn(
        "/api/v1/worker-daemon/sessions",
        Jason.encode!(session_request(workspace, [elixir, "-e", "Process.sleep(:infinity)"], request_id: "request-2", session_id: "session-2"))
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer daemon-token")
      |> Api.call(opts)

    assert worker_full_conn.status == 429
    assert %{"code" => "worker_full", "retryable" => true} = Jason.decode!(worker_full_conn.resp_body)

    assert {:ok, pid} = Session.Supervisor.lookup(registry, "session-1")
    assert :ok = Session.Server.cleanup(pid)
  end

  defp start_daemon_core!(opts) do
    registry = __MODULE__.DaemonRegistry
    capacity = __MODULE__.DaemonCapacity
    supervisor = __MODULE__.DaemonSessionSupervisor

    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({CapacityManager, name: capacity, max_sessions: Keyword.get(opts, :max_sessions, 1)})
    start_supervised!({Session.Supervisor, name: supervisor})

    %{registry: registry, capacity: capacity, supervisor: supervisor}
  end

  defp session_request(workspace, argv, opts \\ []) do
    %{
      "protocol_version" => SymphonyWorkerDaemon.Protocol.protocol_version(),
      "request_id" => Keyword.get(opts, :request_id, "request-1"),
      "session_id" => Keyword.get(opts, :session_id, "session-1"),
      "run_id" => Keyword.get(opts, :run_id, "run-1"),
      "caller" =>
        %{
          "provider_kind" => "fake",
          "worker_pool" => "coding-linux",
          "owner" => Keyword.get(opts, :owner, "symphony"),
          "tenant_id" => Keyword.get(opts, :tenant_id)
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new(),
      "command" => %{"mode" => "argv", "argv" => argv},
      "workspace" => %{"cwd" => workspace},
      "env" => %{}
    }
  end

  defp maybe_put_json_content_type(conn, nil), do: conn
  defp maybe_put_json_content_type(conn, _body), do: put_req_header(conn, "content-type", "application/json")

  defp assert_eventually(fun, attempts \\ 40)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    case fun.() do
      false ->
        Process.sleep(25)
        assert_eventually(fun, attempts - 1)

      nil ->
        Process.sleep(25)
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

  defp wait_for_port_os_pid!(port, attempts_remaining \\ 20)

  defp wait_for_port_os_pid!(port, attempts_remaining) when attempts_remaining > 0 do
    case PlatformProcess.port_os_pid(port) do
      os_pid when is_integer(os_pid) and os_pid > 0 ->
        os_pid

      _none ->
        Process.sleep(25)
        wait_for_port_os_pid!(port, attempts_remaining - 1)
    end
  end

  defp wait_for_port_os_pid!(_port, 0), do: flunk("port os_pid was not available")

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-worker-daemon-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp executable_file!(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\nexit 0\n")
    :ok = File.chmod(path, 0o755)
    path
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

  defp free_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  @process_names %{
    "Capacity" => __MODULE__.Capacity,
    "TenantCapacity" => __MODULE__.TenantCapacity,
    "SessionLedgerNoRestart" => __MODULE__.SessionLedgerNoRestart,
    "AuthRateLimiter" => __MODULE__.AuthRateLimiter,
    "ApiRateLimiter" => __MODULE__.ApiRateLimiter,
    "MissingRegistry" => __MODULE__.MissingRegistry,
    "CreateRateLimiter" => __MODULE__.CreateRateLimiter,
    "Session.Ledger" => __MODULE__.SessionLedger,
    "SessionLedgerRestarted" => __MODULE__.SessionLedgerRestarted,
    "OrphanSweepLedger" => __MODULE__.OrphanSweepLedger,
    "OrphanSweepRegistry" => __MODULE__.OrphanSweepRegistry,
    "OrphanSweepCapacity" => __MODULE__.OrphanSweepCapacity,
    "OrphanSweepSessionSupervisor" => __MODULE__.OrphanSweepSessionSupervisor,
    "OrphanSweepApplication" => __MODULE__.OrphanSweepApplication,
    "SessionLedgerApi" => __MODULE__.SessionLedgerApi,
    "SessionLedgerApiRestarted" => __MODULE__.SessionLedgerApiRestarted,
    "LedgerHealthCapacity" => __MODULE__.LedgerHealthCapacity,
    "LedgerHealth" => __MODULE__.LedgerHealth
  }

  defp unique_name(prefix), do: Map.fetch!(@process_names, prefix)
end
