defmodule SymphonyWorkerDaemon.CLI.ServerSpecTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.CLI.ServerSpec

  test "builds daemon and API children with shared resource names" do
    opts = [
      ip: {127, 0, 0, 1},
      port: 4101,
      token: "daemon-token",
      owner: "owner-a",
      tenant_id: "tenant-a",
      registry: __MODULE__.Registry,
      capacity_manager: __MODULE__.Capacity,
      rate_limiter: __MODULE__.RateLimiter,
      session_ledger: __MODULE__.Ledger,
      session_supervisor: __MODULE__.SessionSupervisor,
      daemon_supervisor_name: __MODULE__.DaemonSupervisor,
      workspace_roots: ["/work"],
      worker_id: "worker-a",
      daemon_instance_id: "daemon-a",
      worker_profile_version: "profile-v1",
      max_sessions: 2,
      max_sessions_per_tenant: 1,
      rate_limit_window_ms: 30_000,
      unauthenticated_rate_limit: 20,
      api_rate_limit: 200,
      session_create_rate_limit: 10,
      allowed_executables: [%{"path" => "/bin/echo"}],
      allow_any_executable?: true,
      enable_dynamic_tool_bridge_proxy?: true,
      allowed_dynamic_tool_bridge_upstreams: ["https://tools.example/api"]
    ]

    assert [
             {SymphonyWorkerDaemon.Application, daemon_opts},
             {Bandit, bandit_opts}
           ] = ServerSpec.children(opts)

    assert Keyword.fetch!(daemon_opts, :name) == __MODULE__.DaemonSupervisor
    assert Keyword.fetch!(daemon_opts, :registry) == __MODULE__.Registry
    assert Keyword.fetch!(daemon_opts, :capacity_manager) == __MODULE__.Capacity
    assert Keyword.fetch!(daemon_opts, :rate_limiter) == __MODULE__.RateLimiter
    assert Keyword.fetch!(daemon_opts, :session_ledger) == __MODULE__.Ledger
    assert Keyword.fetch!(daemon_opts, :session_supervisor) == __MODULE__.SessionSupervisor
    assert Keyword.fetch!(daemon_opts, :workspace_roots) == ["/work"]
    assert Keyword.fetch!(daemon_opts, :max_sessions) == 2

    assert Keyword.fetch!(bandit_opts, :scheme) == :http
    assert Keyword.fetch!(bandit_opts, :ip) == {127, 0, 0, 1}
    assert Keyword.fetch!(bandit_opts, :port) == 4101
    assert {SymphonyWorkerDaemon.Api, api_opts} = Keyword.fetch!(bandit_opts, :plug)
    assert Keyword.fetch!(api_opts, :registry) == __MODULE__.Registry
    assert Keyword.fetch!(api_opts, :worker_id) == "worker-a"
    assert Keyword.fetch!(api_opts, :daemon_instance_id) == "daemon-a"
    assert Keyword.fetch!(api_opts, :allowed_executables) == [%{"path" => "/bin/echo"}]
    assert Keyword.fetch!(api_opts, :enable_dynamic_tool_bridge_proxy?)
    assert Keyword.fetch!(api_opts, :allowed_dynamic_tool_bridge_upstreams) == ["https://tools.example/api"]
  end
end
