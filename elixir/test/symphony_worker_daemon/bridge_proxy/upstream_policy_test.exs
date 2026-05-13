defmodule SymphonyWorkerDaemon.BridgeProxy.UpstreamPolicyTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.BridgeProxy.UpstreamPolicy

  @base_path "/api/v1/agent-tools/dynamic"
  @loopback_url "http://127.0.0.1:4521/api/v1/agent-tools/dynamic"

  test "prepare_allowed_upstreams normalizes and deduplicates upstream base URLs" do
    assert UpstreamPolicy.prepare_allowed_upstreams([
             "HTTPS://Tools.Example.com:443#{@base_path}/",
             "https://tools.example.com#{@base_path}",
             "http://tools.example.com:8080#{@base_path}"
           ]) ==
             {:ok, ["https://tools.example.com#{@base_path}", "http://tools.example.com:8080#{@base_path}"]}
  end

  test "prepare_allowed_upstreams rejects invalid upstream base URLs" do
    assert UpstreamPolicy.prepare_allowed_upstreams(["ftp://tools.example.com#{@base_path}"]) ==
             {:error, {:invalid_dynamic_tool_bridge_allowed_upstream, "ftp://tools.example.com#{@base_path}", :dynamic_tool_bridge_upstream_base_url_invalid}}
  end

  test "base_url requires a configured allowlist" do
    assert UpstreamPolicy.base_url(%{"symphony_base_url" => @loopback_url}, []) ==
             {:error, :dynamic_tool_bridge_upstream_allowlist_missing}
  end

  test "base_url applies upstream address policy" do
    assert UpstreamPolicy.base_url(%{"symphony_base_url" => @loopback_url}, allowed_dynamic_tool_bridge_upstreams: [@loopback_url]) ==
             {:error, {:dynamic_tool_bridge_upstream_address_blocked, "127.0.0.1", {127, 0, 0, 1}, :loopback}}

    assert UpstreamPolicy.base_url(%{"symphony_base_url" => @loopback_url},
             allowed_dynamic_tool_bridge_upstreams: [@loopback_url],
             allow_private_dynamic_tool_bridge_upstreams?: true
           ) == {:ok, @loopback_url}
  end
end
