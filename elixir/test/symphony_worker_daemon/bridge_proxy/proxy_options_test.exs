defmodule SymphonyWorkerDaemon.BridgeProxy.ProxyOptionsTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.BridgeProxy.ProxyOptions

  @base_url_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"
  @token_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN"
  @transport_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT"

  test "projects proxy enablement and upstream token policy" do
    assert :ok = ProxyOptions.ensure_enabled(enable_dynamic_tool_bridge_proxy?: true)
    assert {:error, :dynamic_tool_bridge_proxy_disabled} = ProxyOptions.ensure_enabled([])

    assert {:ok, "token-a"} = ProxyOptions.upstream_token(%{"token" => " token-a "})
    assert {:error, :dynamic_tool_bridge_upstream_token_missing} = ProxyOptions.upstream_token(%{"token" => " "})
    assert {:error, :dynamic_tool_bridge_upstream_token_missing} = ProxyOptions.upstream_token(%{})
  end

  test "builds plug opts without nil values" do
    requester = fn _method, _url, _headers, _body, _opts -> {:ok, 200, %{}} end

    opts =
      ProxyOptions.plug_opts("https://tools.example/api", "upstream-token", "session-token",
        bridge_proxy_requester: requester,
        bridge_proxy_timeout_ms: 12_000,
        max_header_bytes: nil,
        max_request_body_bytes: 2048
      )

    assert Keyword.fetch!(opts, :upstream_base_url) == "https://tools.example/api"
    assert Keyword.fetch!(opts, :upstream_token) == "upstream-token"
    assert Keyword.fetch!(opts, :session_token) == "session-token"
    assert Keyword.fetch!(opts, :requester) == requester
    assert Keyword.fetch!(opts, :timeout_ms) == 12_000
    assert Keyword.fetch!(opts, :max_request_body_bytes) == 2048
    refute Keyword.has_key?(opts, :max_header_bytes)
  end

  test "projects provider environment" do
    env = ProxyOptions.provider_env(4123, "session-token")

    assert env[@base_url_env] == "http://127.0.0.1:4123/api/v1/agent-tools/dynamic"
    assert env[@token_env] == "session-token"
    assert env[@transport_env] == "worker_daemon_http"
  end

  test "validates explicit proxy ports" do
    assert {:ok, 4100} = ProxyOptions.port(bridge_proxy_port: 4100)
    assert {:error, {:invalid_dynamic_tool_bridge_proxy_port, 0}} = ProxyOptions.port(bridge_proxy_port: 0)
    assert {:error, {:invalid_dynamic_tool_bridge_proxy_port, 65_536}} = ProxyOptions.port(bridge_proxy_port: 65_536)
  end
end
