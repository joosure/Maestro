defmodule SymphonyWorkerDaemon.Api.SessionOptionsTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Api.SessionOptions
  alias SymphonyWorkerDaemon.CapacityManager

  test "build projects daemon options used by session startup" do
    opts =
      SessionOptions.build(
        registry: MyRegistry,
        capacity_manager: MyCapacity,
        session_ledger: MyLedger,
        workspace_roots: ["/workspace"],
        worker_id: "worker-1",
        daemon_instance_id: "daemon-1",
        allow_shell?: true,
        allowed_executables: ["/bin/echo"],
        allow_any_executable?: true,
        max_sessions_per_tenant: 2,
        line: :stdout,
        bridge_proxy_requester: MyRequester,
        bridge_proxy_timeout_ms: 1_000,
        bridge_proxy_port: 4100,
        dynamic_tool_bridge_session_token: "token",
        enable_dynamic_tool_bridge_proxy?: true,
        allowed_dynamic_tool_bridge_upstreams: ["https://tools.example"],
        allow_private_dynamic_tool_bridge_upstreams?: true,
        max_header_bytes: 100,
        max_request_body_bytes: 200,
        output_buffer_limit: 300
      )

    assert Keyword.fetch!(opts, :registry) == MyRegistry
    assert Keyword.fetch!(opts, :capacity_manager) == MyCapacity
    assert Keyword.fetch!(opts, :session_ledger) == MyLedger
    assert Keyword.fetch!(opts, :workspace_roots) == ["/workspace"]
    assert Keyword.fetch!(opts, :worker_id) == "worker-1"
    assert Keyword.fetch!(opts, :daemon_instance_id) == "daemon-1"
    assert Keyword.fetch!(opts, :allow_shell?) == true
    assert Keyword.fetch!(opts, :allowed_executables) == ["/bin/echo"]
    assert Keyword.fetch!(opts, :allow_any_executable?) == true
    assert Keyword.fetch!(opts, :max_sessions_per_tenant) == 2
    assert Keyword.fetch!(opts, :line) == :stdout
    assert Keyword.fetch!(opts, :bridge_proxy_requester) == MyRequester
    assert Keyword.fetch!(opts, :bridge_proxy_timeout_ms) == 1_000
    assert Keyword.fetch!(opts, :bridge_proxy_port) == 4100
    assert Keyword.fetch!(opts, :dynamic_tool_bridge_session_token) == "token"
    assert Keyword.fetch!(opts, :enable_dynamic_tool_bridge_proxy?) == true
    assert Keyword.fetch!(opts, :allowed_dynamic_tool_bridge_upstreams) == ["https://tools.example"]
    assert Keyword.fetch!(opts, :allow_private_dynamic_tool_bridge_upstreams?) == true
    assert Keyword.fetch!(opts, :max_header_bytes) == 100
    assert Keyword.fetch!(opts, :max_request_body_bytes) == 200
    assert Keyword.fetch!(opts, :output_buffer_limit) == 300
  end

  test "build applies session startup defaults" do
    opts = SessionOptions.build([])

    assert Keyword.fetch!(opts, :registry) == SymphonyWorkerDaemon.SessionRegistry
    assert Keyword.fetch!(opts, :capacity_manager) == CapacityManager
    assert Keyword.fetch!(opts, :workspace_roots) == []
    assert Keyword.fetch!(opts, :allow_shell?) == false
    assert Keyword.fetch!(opts, :allowed_executables) == []
    assert Keyword.fetch!(opts, :allow_any_executable?) == false
    assert Keyword.fetch!(opts, :enable_dynamic_tool_bridge_proxy?) == false
    assert Keyword.fetch!(opts, :allowed_dynamic_tool_bridge_upstreams) == []
    assert Keyword.fetch!(opts, :allow_private_dynamic_tool_bridge_upstreams?) == false
  end
end
