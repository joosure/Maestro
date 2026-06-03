defmodule SymphonyElixir.Agent.Runtime.WorkerDaemonTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.Runtime
  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Handle, Target}
  alias SymphonyElixir.Agent.Runtime.Executor.WorkerDaemon
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.{Client, EndpointState, EventStream, SessionHandle}
  alias SymphonyElixir.Config.Schema
  alias SymphonyWorkerDaemon.Protocol

  defmodule FakeClient do
    def create_session(command_spec, target, opts) do
      owner = Keyword.fetch!(opts, :test_owner)
      send(owner, {:create_session, command_spec, target, opts})

      {:ok,
       SessionHandle.new(
         endpoint: "http://daemon.example",
         session_id: "daemon-session-1",
         worker_id: "worker-1",
         lease_id: "lease-1",
         client: __MODULE__,
         metadata: %{owner: owner}
       )}
    end

    def send_input(%SessionHandle{metadata: %{owner: owner}}, data, _opts) do
      send(owner, {:send_input, IO.iodata_to_binary(data)})
      :ok
    end

    def stop_session(%SessionHandle{metadata: %{owner: owner}}, _opts) do
      send(owner, :stop_session)
      :ok
    end

    def cleanup_session(%SessionHandle{metadata: %{owner: owner}}, _opts) do
      send(owner, :cleanup_session)
      :ok
    end

    def session_status(%SessionHandle{}, _opts), do: {:ok, "running"}
  end

  defmodule FailoverClient do
    def create_session(_command_spec, %Target{} = target, opts) do
      owner = Keyword.fetch!(opts, :test_owner)
      endpoint = target.metadata.worker_daemon_endpoint
      send(owner, {:failover_create_session, endpoint, target.metadata, Keyword.get(opts, :request_id)})

      case endpoint do
        "http://daemon-full" ->
          {:error, {:worker_daemon_error, :post, 429, "worker_full", %{"code" => "worker_full"}}}

        "http://daemon-ready" ->
          {:ok,
           SessionHandle.new(
             endpoint: endpoint,
             session_id: "daemon-session-ready",
             worker_id: "worker-ready",
             lease_id: "lease-ready",
             client: __MODULE__,
             metadata: %{worker_daemon_endpoint: endpoint}
           )}
      end
    end

    def send_input(%SessionHandle{}, _data, _opts), do: :ok
    def stop_session(%SessionHandle{}, _opts), do: :ok
    def cleanup_session(%SessionHandle{}, _opts), do: :ok
    def session_status(%SessionHandle{}, _opts), do: {:ok, "running"}
  end

  defmodule EventStreamClient do
    def session_events(%SessionHandle{metadata: %{mode: :no_block}}, _opts), do: {:ok, []}

    def session_events(%SessionHandle{metadata: %{test_pid: test_pid}}, opts) do
      send(test_pid, {:session_events, self(), opts})

      receive do
        {:session_events_reply, events} -> {:ok, events}
        {:session_events_error, reason} -> {:error, reason}
      after
        1_000 -> {:error, :test_timeout}
      end
    end

    def session_status(%SessionHandle{metadata: %{mode: :no_block}}, _opts), do: {:ok, "running"}

    def session_status(%SessionHandle{metadata: %{test_pid: test_pid}}, opts) do
      send(test_pid, {:session_status, self(), opts})

      receive do
        {:session_status_reply, status} -> {:ok, status}
        {:session_status_error, reason} -> {:error, reason}
      after
        1_000 -> {:error, :test_timeout}
      end
    end
  end

  setup do
    previous_endpoint = Application.get_env(:symphony_elixir, :worker_daemon_endpoint)
    previous_endpoints = Application.get_env(:symphony_elixir, :worker_daemon_endpoints)
    previous_pools = Application.get_env(:symphony_elixir, :worker_daemon_pools)
    previous_token = Application.get_env(:symphony_elixir, :worker_daemon_token)
    previous_endpoint_env = System.get_env("SYMPHONY_WORKER_DAEMON_ENDPOINT")
    previous_endpoints_env = System.get_env("SYMPHONY_WORKER_DAEMON_ENDPOINTS")

    Application.delete_env(:symphony_elixir, :worker_daemon_endpoint)
    Application.delete_env(:symphony_elixir, :worker_daemon_endpoints)
    Application.delete_env(:symphony_elixir, :worker_daemon_pools)
    Application.delete_env(:symphony_elixir, :worker_daemon_token)
    System.delete_env("SYMPHONY_WORKER_DAEMON_ENDPOINT")
    System.delete_env("SYMPHONY_WORKER_DAEMON_ENDPOINTS")

    ensure_worker_daemon_runtime_support!()
    EndpointState.reset()

    on_exit(fn ->
      restore_env(:worker_daemon_endpoint, previous_endpoint)
      restore_env(:worker_daemon_endpoints, previous_endpoints)
      restore_env(:worker_daemon_pools, previous_pools)
      restore_env(:worker_daemon_token, previous_token)
      restore_system_env("SYMPHONY_WORKER_DAEMON_ENDPOINT", previous_endpoint_env)
      restore_system_env("SYMPHONY_WORKER_DAEMON_ENDPOINTS", previous_endpoints_env)
      EndpointState.reset()
    end)

    :ok
  end

  test "runtime resolves worker_daemon target with explicit endpoint" do
    workspace = tmp_workspace!("resolve")

    assert {:ok, %Target{} = target} =
             Runtime.resolve_target(workspace,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "coding-linux",
               worker_daemon_endpoint: "http://daemon.example/",
               worker_daemon_worker_id: "worker-1"
             )

    assert target.placement == :worker_daemon
    assert target.executor == WorkerDaemon
    assert target.worker_pool == "coding-linux"
    assert target.metadata.worker_daemon_endpoint == "http://daemon.example"
    assert target.metadata.worker_daemon_worker_id == "worker-1"
    assert Target.remote?(target)
  end

  test "runtime resolves worker_daemon target from endpoint candidates" do
    workspace = tmp_workspace!("pool-endpoints")

    requester = fn
      :get, "http://daemon-full/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        {:ok, 200,
         ready_health_payload("worker-full")
         |> Map.put("status", "full")}

      :get, "http://daemon-ready/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        {:ok, 200, ready_health_payload("worker-ready", "daemon-instance-ready")}
    end

    assert {:ok, %Target{} = target} =
             Runtime.resolve_target(workspace,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "coding-linux",
               worker_daemon_endpoints: ["http://daemon-full/", "http://daemon-ready/"],
               worker_daemon_requester: requester
             )

    assert target.metadata.worker_daemon_endpoint == "http://daemon-ready"
    assert target.metadata.worker_daemon_worker_id == "worker-ready"
    assert target.metadata.worker_daemon_daemon_instance_id == "daemon-instance-ready"
    assert target.metadata.worker_daemon_endpoint_source == "opts.worker_daemon_endpoints"
    assert target.metadata.worker_daemon_health.status == "ready"
  end

  test "runtime resolves worker_daemon target from named worker pool" do
    workspace = tmp_workspace!("named-pool")

    requester = fn :get, "http://daemon-pool/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
      {:ok, 200, ready_health_payload("worker-pinned", "daemon-instance-pool")}
    end

    assert {:ok, %Target{} = target} =
             Runtime.resolve_target(workspace,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "coding-linux",
               worker_daemon_pools: %{
                 "coding-linux" => [
                   %{id: "pool-endpoint-1", endpoint: "http://daemon-pool/", worker_id: "worker-pinned"}
                 ]
               },
               worker_daemon_requester: requester
             )

    assert target.metadata.worker_daemon_endpoint == "http://daemon-pool"
    assert target.metadata.worker_daemon_worker_id == "worker-pinned"
    assert target.metadata.worker_daemon_endpoint_id == "pool-endpoint-1"
    assert target.metadata.worker_daemon_endpoint_source == "opts.worker_daemon_pools.coding-linux"
  end

  test "runtime resolves worker_daemon target from typed runtime.agent settings" do
    workspace = tmp_workspace!("settings-pool")
    token_env = "SYMPHONY_WORKER_DAEMON_TEST_TOKEN"
    previous_token = System.get_env(token_env)
    System.put_env(token_env, "daemon-secret-token")

    on_exit(fn -> restore_system_env(token_env, previous_token) end)

    assert {:ok, settings} =
             Schema.parse(%{
               "runtime" => %{
                 "agent" => %{
                   "placement" => "worker_daemon",
                   "worker_pool" => "coding-linux",
                   "worker_daemon" => %{
                     "token_env" => token_env,
                     "timeout_ms" => 12_000,
                     "required_features" => ["session_create"],
                     "health_cache_ttl_ms" => 1_500,
                     "circuit_ttl_ms" => 2_500,
                     "pools" => %{
                       "coding-linux" => [
                         %{
                           "id" => "pool-endpoint-1",
                           "endpoint" => "http://daemon-settings/",
                           "worker_id" => "worker-settings"
                         }
                       ]
                     }
                   }
                 }
               }
             })

    requester = fn :get, "http://daemon-settings/api/v1/worker-daemon/health", headers, nil, request_opts ->
      assert {"authorization", "Bearer daemon-secret-token"} in headers
      assert request_opts.timeout_ms == 12_000
      {:ok, 200, ready_health_payload("worker-settings", "daemon-instance-settings")}
    end

    assert {:ok, runtime_context} =
             Runtime.provider_runtime_context(workspace,
               settings: settings,
               worker_daemon_requester: requester
             )

    assert %Target{} = target = runtime_context.agent_runtime_target
    assert target.placement == :worker_daemon
    assert target.worker_pool == "coding-linux"
    assert target.metadata.worker_daemon_endpoint == "http://daemon-settings"
    assert target.metadata.worker_daemon_worker_id == "worker-settings"
    assert target.metadata.worker_daemon_endpoint_id == "pool-endpoint-1"

    assert Keyword.fetch!(runtime_context.executor_opts, :worker_daemon_token) == "daemon-secret-token"
    assert Keyword.fetch!(runtime_context.executor_opts, :worker_daemon_timeout_ms) == 12_000
    assert Keyword.fetch!(runtime_context.executor_opts, :worker_daemon_health_cache_ttl_ms) == 1_500
    assert Keyword.fetch!(runtime_context.executor_opts, :worker_daemon_circuit_ttl_ms) == 2_500

    assert Keyword.fetch!(runtime_context.executor_opts, :worker_daemon_pools) == %{
             "coding-linux" => [
               %{
                 "id" => "pool-endpoint-1",
                 "endpoint" => "http://daemon-settings/",
                 "worker_id" => "worker-settings"
               }
             ]
           }

    refute inspect(target.metadata) =~ "daemon-secret-token"
  end

  test "explicit runtime opts override typed runtime.agent settings" do
    workspace = tmp_workspace!("settings-override")

    assert {:ok, settings} =
             Schema.parse(%{
               "runtime" => %{
                 "agent" => %{
                   "placement" => "worker_daemon",
                   "worker_pool" => "config-pool",
                   "worker_daemon" => %{"endpoint" => "http://daemon-config"}
                 }
               }
             })

    assert {:ok, %Target{} = target} =
             Runtime.resolve_target(workspace,
               settings: settings,
               worker_pool: "override-pool",
               worker_daemon_endpoint: "http://daemon-override"
             )

    assert target.worker_pool == "override-pool"
    assert target.metadata.worker_daemon_endpoint == "http://daemon-override"
  end

  test "typed runtime.agent settings reject unsafe worker_daemon endpoints" do
    assert {:error, {:invalid_workflow_config, message}} =
             Schema.parse(%{
               "runtime" => %{
                 "agent" => %{
                   "placement" => "worker_daemon",
                   "worker_daemon" => %{
                     "endpoint" => "http://user:secret@daemon.example?token=secret"
                   }
                 }
               }
             })

    assert message =~ "must not include userinfo"
  end

  test "top-level agent_runtime config is rejected" do
    assert {:error, {:invalid_workflow_config, message}} =
             Schema.parse(%{
               "agent_runtime" => %{
                 "placement" => "worker_daemon",
                 "worker_daemon" => %{"endpoint" => "http://daemon.example"}
               }
             })

    assert message =~ "agent_runtime has been replaced by runtime.agent"
  end

  test "runtime rejects unsafe explicit worker_daemon endpoints" do
    workspace = tmp_workspace!("unsafe-explicit-endpoint")

    assert {:error,
            {:agent_runtime_target_invalid, :invalid_worker_daemon_endpoint,
             %{
               worker_placement: "worker_daemon",
               reason: {:worker_daemon_endpoint_invalid, %{endpoint: "http://daemon.example", reason: "must not include userinfo"}}
             }}} =
             Runtime.resolve_target(workspace,
               agent_runtime_placement: :worker_daemon,
               worker_daemon_endpoint: "http://user:secret@daemon.example?token=secret"
             )
  end

  test "runtime reports worker_daemon pool failures without local routing" do
    workspace = tmp_workspace!("pool-unavailable")

    requester = fn :get, "http://daemon-full/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
      {:ok, 200,
       ready_health_payload("worker-full")
       |> Map.put("status", "full")}
    end

    assert {:error,
            {:agent_runtime_target_invalid, :worker_daemon_pool_unavailable,
             %{
               worker_placement: "worker_daemon",
               worker_pool: "coding-linux",
               failures: [
                 %{
                   endpoint: "http://daemon-full",
                   reason: %{code: "worker_daemon_not_ready", status: "full"}
                 }
               ]
             }}} =
             Runtime.resolve_target(workspace,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "coding-linux",
               worker_daemon_endpoints: ["http://daemon-full"],
               worker_daemon_requester: requester
             )
  end

  test "runtime reuses short-lived worker_daemon health cache during pool selection" do
    workspace = tmp_workspace!("pool-health-cache")

    requester = fn :get, "http://daemon-ready/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
      send(self(), :daemon_ready_health_called)
      {:ok, 200, ready_health_payload("worker-ready", "daemon-instance-ready")}
    end

    opts = [
      agent_runtime_placement: :worker_daemon,
      worker_pool: "coding-linux",
      worker_daemon_endpoints: ["http://daemon-ready"],
      worker_daemon_health_cache_ttl_ms: 10_000,
      worker_daemon_requester: requester
    ]

    assert {:ok, %Target{} = first_target} = Runtime.resolve_target(workspace, opts)
    assert first_target.metadata.worker_daemon_health_source == "preflight"
    assert_receive :daemon_ready_health_called

    assert {:ok, %Target{} = second_target} = Runtime.resolve_target(workspace, opts)
    assert second_target.metadata.worker_daemon_health_source == "cache"
    refute_receive :daemon_ready_health_called
  end

  test "runtime skips circuit-open worker_daemon endpoint during pool selection" do
    workspace = tmp_workspace!("pool-circuit")

    requester = fn
      :get, "http://daemon-down/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        send(self(), :daemon_down_health_called)
        {:error, :closed}

      :get, "http://daemon-ready/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        send(self(), :daemon_ready_health_called)
        {:ok, 200, ready_health_payload("worker-ready", "daemon-instance-ready")}
    end

    opts = [
      agent_runtime_placement: :worker_daemon,
      worker_pool: "coding-linux",
      worker_daemon_endpoints: ["http://daemon-down", "http://daemon-ready"],
      worker_daemon_health_cache_ttl_ms: 10_000,
      worker_daemon_circuit_ttl_ms: 10_000,
      worker_daemon_requester: requester
    ]

    assert {:ok, %Target{} = first_target} = Runtime.resolve_target(workspace, opts)
    assert first_target.metadata.worker_daemon_endpoint == "http://daemon-ready"
    assert_receive :daemon_down_health_called
    assert_receive :daemon_ready_health_called

    assert {:ok, %Target{} = second_target} = Runtime.resolve_target(workspace, opts)
    assert second_target.metadata.worker_daemon_endpoint == "http://daemon-ready"
    assert second_target.metadata.worker_daemon_health_source == "cache"
    refute_receive :daemon_down_health_called
    refute_receive :daemon_ready_health_called
  end

  test "runtime fails explicitly when worker_daemon endpoint is missing" do
    workspace = tmp_workspace!("missing-endpoint")

    assert {:error, {:agent_runtime_target_invalid, :missing_worker_daemon_endpoint, %{worker_placement: "worker_daemon", worker_pool: "coding-linux"}}} =
             Runtime.resolve_target(workspace,
               agent_runtime_placement: :worker_daemon,
               worker_pool: "coding-linux"
             )
  end

  test "runtime rejects unsupported placement instead of routing to local execution" do
    workspace = tmp_workspace!("unsupported")

    assert {:error, {:agent_runtime_target_invalid, :unsupported_placement, %{worker_placement: "unsupported"}}} =
             Runtime.resolve_target(workspace, agent_runtime_placement: :unsupported_remote)
  end

  test "client creates a daemon session with string-keyed protocol payload" do
    command_spec = CommandSpec.new(argv: ["claude", "-p"], cwd: "/work", env: %{"CLAUDE_CONFIG_DIR" => "/auth"})

    target =
      Target.new(
        placement: :worker_daemon,
        workspace_path: "/work",
        worker_pool: "coding-linux",
        metadata: %{worker_daemon_endpoint: "http://daemon.example", run_id: "run-1", agent_provider_kind: "claude_code"}
      )

    requester = fn
      :get, "http://daemon.example/api/v1/worker-daemon/health", headers, nil, _request_opts ->
        assert {"authorization", "Bearer daemon-token"} in headers

        {:ok, 200,
         %{
           "status" => "ready",
           "protocol_version" => Protocol.protocol_version(),
           "worker_id" => "worker-1",
           "features" => Protocol.supported_features(),
           "capabilities" => [%{"kind" => "executable_policy", "scope" => "any", "available" => true}]
         }}

      :post, "http://daemon.example/api/v1/worker-daemon/sessions", headers, body, _request_opts ->
        assert {"authorization", "Bearer daemon-token"} in headers
        assert body["protocol_version"] == Protocol.protocol_version()
        assert body["run_id"] == "run-1"
        assert body["caller"]["provider_kind"] == "claude_code"
        assert body["caller"]["worker_pool"] == "coding-linux"
        assert body["command"] == %{"mode" => "argv", "argv" => ["claude", "-p"]}
        assert body["workspace"]["cwd"] == "/work"
        assert body["env"]["CLAUDE_CONFIG_DIR"] == "/auth"
        assert body["dynamic_tool_bridge"]["transport"] == "worker_daemon_http"

        {:ok, 201, %{"session_id" => "session-1", "worker_id" => "worker-1", "lease_id" => "lease-1", "status" => "running"}}
    end

    assert {:ok, %SessionHandle{} = handle} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               dynamic_tool_bridge_runtime: %{daemon_bridge: %{"transport" => "worker_daemon_http"}},
               worker_daemon_requester: requester
             )

    assert handle.session_id == "session-1"
    assert handle.worker_id == "worker-1"
    assert handle.lease_id == "lease-1"
    assert handle.metadata.worker_placement == "worker_daemon"
    assert handle.metadata.agent_provider_kind == "claude_code"
  end

  test "client reconciles uncertain create failure through deterministic session status" do
    command_spec = CommandSpec.new(argv: ["claude", "-p"], cwd: "/work")
    target = worker_daemon_target("run-reconcile-status")

    requester = fn
      :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        {:ok, 200, ready_health_payload("worker-1")}

      :post, "http://daemon.example/api/v1/worker-daemon/sessions", _headers, body, _request_opts ->
        assert body["request_id"] == "request-reconcile-status"
        assert body["run_id"] == "run-reconcile-status"
        {:error, :closed}

      :get, "http://daemon.example/api/v1/worker-daemon/sessions/session-request-reconcile-status", _headers, nil, _request_opts ->
        {:ok, 200,
         %{
           "session_id" => "session-request-reconcile-status",
           "worker_id" => "worker-1",
           "daemon_instance_id" => "daemon-instance-1",
           "lease_id" => "lease-reconcile-status",
           "status" => "running"
         }}
    end

    assert {:ok, %SessionHandle{} = handle} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester,
               request_id: "request-reconcile-status"
             )

    assert handle.session_id == "session-request-reconcile-status"
    assert handle.lease_id == "lease-reconcile-status"
    assert handle.metadata.worker_daemon_reconciled == true
    assert handle.metadata.worker_daemon_reconcile_source == "session_status"
  end

  test "client reconciles uncertain server create error through owner-scoped session list" do
    command_spec = CommandSpec.new(argv: ["claude", "-p"], cwd: "/work")
    target = worker_daemon_target("run-reconcile-list")

    requester = fn
      :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        {:ok, 200, ready_health_payload("worker-1")}

      :post, "http://daemon.example/api/v1/worker-daemon/sessions", _headers, body, _request_opts ->
        assert body["request_id"] == "request-reconcile-list"
        {:ok, 503, %{"code" => "daemon_unavailable", "message" => "temporary failure", "retryable" => true}}

      :get, "http://daemon.example/api/v1/worker-daemon/sessions/session-request-reconcile-list", _headers, nil, _request_opts ->
        {:ok, 404, %{"code" => "session_not_found", "message" => "not found"}}

      :get, "http://daemon.example/api/v1/worker-daemon/sessions?owner=symphony&run_id=run-reconcile-list", _headers, nil, _request_opts ->
        {:ok, 200,
         %{
           "sessions" => [
             %{
               "session_id" => "session-request-reconcile-list",
               "status" => "running",
               "run_id" => "run-reconcile-list",
               "owner" => "symphony",
               "lease_id" => "lease-reconcile-list"
             }
           ]
         }}
    end

    assert {:ok, %SessionHandle{} = handle} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester,
               request_id: "request-reconcile-list"
             )

    assert handle.session_id == "session-request-reconcile-list"
    assert handle.lease_id == "lease-reconcile-list"
    assert handle.metadata.worker_daemon_reconciled == true
    assert handle.metadata.worker_daemon_reconcile_source == "session_list"
  end

  test "client does not reconcile deterministic create rejection" do
    command_spec = CommandSpec.new(argv: ["claude", "-p"], cwd: "/work")
    target = worker_daemon_target("run-rejected")

    requester = fn
      :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        {:ok, 200, ready_health_payload("worker-1")}

      :post, "http://daemon.example/api/v1/worker-daemon/sessions", _headers, _body, _request_opts ->
        {:ok, 422, %{"code" => "command_rejected", "message" => "command rejected", "retryable" => false}}
    end

    assert {:error, {:worker_daemon_error, :post, 422, "command_rejected", _payload}} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester,
               request_id: "request-rejected"
             )
  end

  test "client preflight rejects mismatched daemon health before session creation" do
    command_spec = CommandSpec.new(argv: ["claude"], cwd: "/work")

    target =
      Target.new(
        placement: :worker_daemon,
        workspace_path: "/work",
        metadata: %{worker_daemon_endpoint: "http://daemon.example", worker_daemon_worker_id: "worker-expected"}
      )

    requester = fn :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
      {:ok, 200,
       %{
         "status" => "ready",
         "protocol_version" => Protocol.protocol_version(),
         "worker_id" => "worker-other",
         "features" => Protocol.supported_features(),
         "capabilities" => [%{"kind" => "executable_policy", "scope" => "any", "available" => true}]
       }}
    end

    assert {:error, {:worker_daemon_worker_mismatch, "worker-expected", "worker-other"}} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester
             )
  end

  test "client preflight rejects unavailable command capabilities before session creation" do
    command_spec = CommandSpec.new(argv: ["claude"], cwd: "/work")

    target =
      Target.new(
        placement: :worker_daemon,
        workspace_path: "/work",
        metadata: %{worker_daemon_endpoint: "http://daemon.example"}
      )

    requester = fn :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
      {:ok, 200,
       %{
         "status" => "ready",
         "protocol_version" => Protocol.protocol_version(),
         "worker_id" => "worker-1",
         "features" => Protocol.supported_features(),
         "capabilities" => [%{"kind" => "executable", "command" => "codex", "name" => "codex", "path" => "/usr/bin/codex", "available" => true}]
       }}
    end

    assert {:error, {:worker_daemon_command_not_available, %{command: "claude", name: "claude"}}} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester
             )
  end

  test "client preflight requires session events when stream forwarding is enabled" do
    command_spec = CommandSpec.new(argv: ["claude"], cwd: "/work")

    target =
      Target.new(
        placement: :worker_daemon,
        workspace_path: "/work",
        metadata: %{worker_daemon_endpoint: "http://daemon.example"}
      )

    requester = fn :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
      {:ok, 200, ready_health_payload("worker-1") |> Map.put("features", Protocol.supported_features() -- ["session_events"])}
    end

    assert {:error, {:worker_daemon_missing_features, ["session_events"]}} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester,
               worker_daemon_stream_events?: true
             )
  end

  test "client preflight requires dynamic tool bridge proxy when daemon bridge is requested" do
    command_spec = CommandSpec.new(argv: ["claude"], cwd: "/work")

    target =
      Target.new(
        placement: :worker_daemon,
        workspace_path: "/work",
        metadata: %{worker_daemon_endpoint: "http://daemon.example"}
      )

    requester = fn
      :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        features = Protocol.supported_features() -- ["dynamic_tool_bridge_proxy"]
        {:ok, 200, ready_health_payload("worker-1") |> Map.put("features", features)}
    end

    assert {:error, {:worker_daemon_missing_features, ["dynamic_tool_bridge_proxy"]}} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester,
               dynamic_tool_bridge_runtime: %{daemon_bridge: %{"transport" => "worker_daemon_http"}}
             )
  end

  test "client lists owner-scoped daemon sessions for reconciliation" do
    target =
      Target.new(
        placement: :worker_daemon,
        workspace_path: "/work",
        metadata: %{worker_daemon_endpoint: "http://daemon.example", run_id: "run-1"}
      )

    requester = fn :get, "http://daemon.example/api/v1/worker-daemon/sessions?owner=symphony&run_id=run-1", headers, nil, _request_opts ->
      assert {"authorization", "Bearer daemon-token"} in headers

      {:ok, 200,
       %{
         "sessions" => [
           %{"session_id" => "session-1", "status" => "running", "run_id" => "run-1", "owner" => "symphony"}
         ]
       }}
    end

    assert {:ok, [%{session_id: "session-1", status: "running", run_id: "run-1", owner: "symphony"}]} =
             Client.list_sessions(target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester
             )
  end

  test "protocol preserves session event data exactly" do
    assert {:ok, [%{data: "  {\"type\":\"result\"}\n"}]} =
             Protocol.normalize_session_events_response(%{
               "events" => [
                 %{
                   "event_id" => 1,
                   "type" => "output",
                   "stream" => "stdout",
                   "data" => "  {\"type\":\"result\"}\n"
                 }
               ]
             })
  end

  test "protocol error payloads redact nested secret fields" do
    assert {:worker_daemon_error, :post, 500, "provider_failed", payload} =
             Protocol.error_reason(:post, 500, %{
               code: "provider_failed",
               message: "token=secret-value",
               details: %{token: "secret-value", nested: [%{password: "secret-value"}]}
             })

    refute inspect(payload) =~ "secret-value"
    assert inspect(payload) =~ "[REDACTED]"
  end

  test "session handle safe metadata redacts unsafe extras and preserves daemon identifiers" do
    handle =
      SessionHandle.new(
        endpoint: "http://daemon.example",
        session_id: "session-safe",
        worker_id: "worker-safe",
        daemon_instance_id: "daemon-safe",
        lease_id: "lease-safe",
        metadata: %{
          worker_daemon_session_id: "spoofed-session",
          token: "secret-value",
          nested: %{password: "secret-value"},
          note: "TOKEN=secret-value"
        }
      )

    metadata = SessionHandle.safe_metadata(handle)

    assert metadata.worker_daemon_session_id == "session-safe"
    assert metadata.worker_daemon_worker_id == "worker-safe"
    assert metadata.worker_daemon_instance_id == "daemon-safe"
    assert metadata.worker_daemon_lease_id == "lease-safe"
    refute inspect(metadata) =~ "secret-value"
    assert inspect(metadata) =~ "[REDACTED]"
  end

  test "client can forward daemon session events as port-like messages" do
    command_spec = CommandSpec.new(argv: ["claude", "-p"], cwd: "/work")
    target = worker_daemon_target("run-stream-events")

    requester = fn
      :get, "http://daemon.example/api/v1/worker-daemon/health", _headers, nil, _request_opts ->
        {:ok, 200, ready_health_payload("worker-1")}

      :post, "http://daemon.example/api/v1/worker-daemon/sessions", _headers, _body, _request_opts ->
        {:ok, 201, %{"session_id" => "session-stream-events", "worker_id" => "worker-1", "status" => "running"}}

      :get, "http://daemon.example/api/v1/worker-daemon/sessions/session-stream-events/events?after_event_id=0&limit=10", _headers, nil, _request_opts ->
        {:ok, 200, %{"events" => [%{"event_id" => 1, "type" => "output", "stream" => "stdout", "data" => "{\"type\":\"result\"}\n"}]}}

      :get, "http://daemon.example/api/v1/worker-daemon/sessions/session-stream-events", _headers, nil, _request_opts ->
        {:ok, 200, %{"session_id" => "session-stream-events", "status" => "exited"}}
    end

    assert {:ok, %SessionHandle{} = handle} =
             Client.create_session(command_spec, target,
               worker_daemon_token: "daemon-token",
               worker_daemon_requester: requester,
               worker_daemon_stream_events?: true,
               worker_daemon_stream_event_limit: 10,
               request_id: "request-stream-events"
             )

    assert_receive {^handle, {:data, {:eol, "{\"type\":\"result\"}"}}}
    assert_receive {^handle, {:exit_status, 0}}
  end

  test "event stream preserves port-like line framing for daemon output chunks" do
    handle =
      SessionHandle.new(
        endpoint: "http://daemon.example",
        session_id: "session-stream-line-framing",
        client: EventStreamClient,
        metadata: %{test_pid: self()}
      )

    assert {:ok, stream_pid} =
             EventStream.start_link(
               handle: handle,
               owner: self(),
               opts: [worker_daemon_stream_poll_interval_ms: 10, worker_daemon_stream_event_limit: 10]
             )

    assert_receive {:session_events, ^stream_pid, _event_opts}

    send(stream_pid, {
      :session_events_reply,
      [
        %{event_id: 1, type: "output", data: "partial"},
        %{event_id: 2, type: "output", data: " line\nsecond line\nthird"}
      ]
    })

    assert_receive {^handle, {:data, {:noeol, "partial"}}}
    assert_receive {^handle, {:data, {:eol, " line"}}}
    assert_receive {^handle, {:data, {:eol, "second line"}}}
    assert_receive {^handle, {:data, {:noeol, "third"}}}

    assert_receive {:session_status, ^stream_pid, _status_opts}
    send(stream_pid, {:session_status_reply, "exited"})
    assert_receive {^handle, {:exit_status, 0}}
  end

  test "event stream advances event cursor and does not replay forwarded output" do
    handle =
      SessionHandle.new(
        endpoint: "http://daemon.example",
        session_id: "session-stream-cursor",
        client: EventStreamClient,
        metadata: %{test_pid: self()}
      )

    assert {:ok, stream_pid} =
             EventStream.start_link(
               handle: handle,
               owner: self(),
               opts: [worker_daemon_stream_poll_interval_ms: 10, worker_daemon_stream_event_limit: 2]
             )

    assert_receive {:session_events, ^stream_pid, first_event_opts}
    assert Keyword.fetch!(first_event_opts, :after_event_id) == 0
    assert Keyword.fetch!(first_event_opts, :limit) == 2
    send(stream_pid, {:session_events_reply, [%{event_id: 1, type: "output", data: "first\n"}]})
    assert_receive {^handle, {:data, {:eol, "first"}}}

    assert_receive {:session_status, ^stream_pid, _first_status_opts}
    send(stream_pid, {:session_status_reply, "running"})

    assert_receive {:session_events, ^stream_pid, second_event_opts}
    assert Keyword.fetch!(second_event_opts, :after_event_id) == 1
    send(stream_pid, {:session_events_reply, [%{event_id: 2, type: "output", data: "second\n"}]})
    assert_receive {^handle, {:data, {:eol, "second"}}}
    refute_receive {^handle, {:data, {:eol, "first"}}}

    assert_receive {:session_status, ^stream_pid, _second_status_opts}
    send(stream_pid, {:session_status_reply, "exited"})
    assert_receive {^handle, {:exit_status, 0}}
  end

  test "event stream maps non-success terminal daemon status to failing exit status" do
    handle =
      SessionHandle.new(
        endpoint: "http://daemon.example",
        session_id: "session-stream-failed",
        client: EventStreamClient,
        metadata: %{test_pid: self()}
      )

    assert {:ok, stream_pid} = EventStream.start_link(handle: handle, owner: self(), opts: [])

    assert_receive {:session_events, ^stream_pid, _event_opts}
    send(stream_pid, {:session_events_reply, []})

    assert_receive {:session_status, ^stream_pid, _status_opts}
    send(stream_pid, {:session_status_reply, "failed"})

    assert_receive {^handle, {:exit_status, 1}}
  end

  test "event stream maps daemon status polling errors to failing exit status" do
    handle =
      SessionHandle.new(
        endpoint: "http://daemon.example",
        session_id: "session-stream-status-error",
        client: EventStreamClient,
        metadata: %{test_pid: self()}
      )

    assert {:ok, stream_pid} = EventStream.start_link(handle: handle, owner: self(), opts: [])
    ref = Process.monitor(stream_pid)

    assert_receive {:session_events, ^stream_pid, _event_opts}
    send(stream_pid, {:session_events_reply, []})

    assert_receive {:session_status, ^stream_pid, _status_opts}
    send(stream_pid, {:session_status_error, :closed})

    assert_receive {^handle, {:exit_status, 1}}
    assert_receive {:DOWN, ^ref, :process, ^stream_pid, :normal}
  end

  test "event stream stops when its owner process exits" do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    handle =
      SessionHandle.new(
        endpoint: "http://daemon.example",
        session_id: "session-stream-owner-down",
        client: EventStreamClient,
        metadata: %{mode: :no_block}
      )

    assert {:ok, stream_pid} =
             EventStream.start_link(
               handle: handle,
               owner: owner,
               opts: [worker_daemon_stream_poll_interval_ms: 10]
             )

    ref = Process.monitor(stream_pid)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^stream_pid, :normal}, 1_000
  end

  test "executor start, input, alive, stop, and cleanup delegate through the daemon client" do
    command_spec = CommandSpec.new(command: "exec claude", cwd: "/work")
    target = Target.new(placement: :worker_daemon, workspace_path: "/work")

    assert {:ok, %SessionHandle{} = handle} =
             WorkerDaemon.start(command_spec, target,
               worker_daemon_client: FakeClient,
               test_owner: self()
             )

    assert_receive {:create_session, ^command_spec, ^target, create_opts}
    assert Keyword.fetch!(create_opts, :worker_daemon_stream_events?) == true
    assert is_binary(Keyword.fetch!(create_opts, :request_id))
    assert WorkerDaemon.alive?(handle)
    assert Handle.command(handle, "hello\n")
    assert_receive {:send_input, "hello\n"}

    assert :ok = WorkerDaemon.stop(handle)
    assert_receive :stop_session
    assert_receive :cleanup_session
  end

  test "executor retries next pool candidate when selected daemon is full during create" do
    command_spec = CommandSpec.new(argv: ["claude", "-p"], cwd: "/work")

    target =
      Target.new(
        placement: :worker_daemon,
        worker_pool: "coding-linux",
        workspace_path: "/work",
        metadata: %{
          worker_daemon_endpoint: "http://daemon-full",
          worker_daemon_worker_id: "worker-full",
          worker_daemon_endpoint_source: "opts.worker_daemon_endpoints"
        }
      )

    assert {:ok, %SessionHandle{} = handle} =
             WorkerDaemon.start(command_spec, target,
               worker_daemon_client: FailoverClient,
               worker_daemon_endpoints: [
                 %{endpoint: "http://daemon-full", worker_id: "worker-full"},
                 %{endpoint: "http://daemon-ready", worker_id: "worker-ready"}
               ],
               test_owner: self()
             )

    assert handle.endpoint == "http://daemon-ready"

    assert handle.metadata.worker_daemon_create_failover_failures == [
             %{
               endpoint: "http://daemon-full",
               worker_id: "worker-full",
               source: "opts.worker_daemon_endpoints",
               reason: %{code: "worker_full", status: 429}
             }
           ]

    assert_receive {:failover_create_session, "http://daemon-full", %{worker_daemon_worker_id: "worker-full"}, request_id}
    assert_receive {:failover_create_session, "http://daemon-ready", %{worker_daemon_worker_id: "worker-ready"}, ^request_id}
    assert is_binary(request_id)
    assert {:open, %{reason: %{code: "worker_full"}}} = EndpointState.circuit_status("http://daemon-full")
  end

  test "executor does not pool-failover when an explicit daemon endpoint is configured" do
    command_spec = CommandSpec.new(argv: ["claude", "-p"], cwd: "/work")

    target =
      Target.new(
        placement: :worker_daemon,
        worker_pool: "coding-linux",
        workspace_path: "/work",
        metadata: %{worker_daemon_endpoint: "http://daemon-full", worker_daemon_worker_id: "worker-full"}
      )

    assert {:error, {:worker_daemon_error, :post, 429, "worker_full", _payload}} =
             WorkerDaemon.start(command_spec, target,
               worker_daemon_client: FailoverClient,
               worker_daemon_endpoint: "http://daemon-full",
               worker_daemon_endpoints: [
                 %{endpoint: "http://daemon-full", worker_id: "worker-full"},
                 %{endpoint: "http://daemon-ready", worker_id: "worker-ready"}
               ],
               test_owner: self()
             )

    assert_receive {:failover_create_session, "http://daemon-full", %{worker_daemon_worker_id: "worker-full"}, request_id}
    assert is_binary(request_id)
    refute_receive {:failover_create_session, "http://daemon-ready", _metadata, _request_id}
  end

  defp restore_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_env(key, value), do: Application.put_env(:symphony_elixir, key, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)

  defp ensure_worker_daemon_runtime_support! do
    SymphonyElixir.TestSupport.restart_supervised_child(EndpointState)
    SymphonyElixir.TestSupport.restart_supervised_child(SymphonyElixir.Agent.Runtime.WorkerDaemon.EventStreamSupervisor)
  end

  defp ready_health_payload(worker_id, daemon_instance_id \\ "daemon-instance-1") do
    %{
      "status" => "ready",
      "protocol_version" => Protocol.protocol_version(),
      "worker_id" => worker_id,
      "daemon_instance_id" => daemon_instance_id,
      "features" => Protocol.supported_features(),
      "capabilities" => [%{"kind" => "executable_policy", "scope" => "any", "available" => true}]
    }
  end

  defp worker_daemon_target(run_id) do
    Target.new(
      placement: :worker_daemon,
      workspace_path: "/work",
      worker_pool: "coding-linux",
      metadata: %{worker_daemon_endpoint: "http://daemon.example", run_id: run_id, agent_provider_kind: "claude_code"}
    )
  end

  defp tmp_workspace!(suffix) do
    path = Path.join(System.tmp_dir!(), "symphony-worker-daemon-#{suffix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
