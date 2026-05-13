defmodule SymphonyWorkerDaemon.ConfigTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Config

  test "normalizes CLI options into a typed daemon config" do
    root = Path.expand("tmp/worker-daemon-config")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    assert {:ok, %Config{} = config} =
             Config.normalize_cli_options(
               [
                 workspace_root: root,
                 allow_executable: elixir,
                 token: "daemon-token",
                 owner: "control-plane-a",
                 tenant_id: "tenant-a",
                 session_ledger_path: "tmp/session-ledger.json",
                 worker_id: "worker-a",
                 daemon_instance_id: "daemon-a",
                 worker_profile_version: "profile-v1",
                 max_sessions: 4
               ],
               deps(root)
             )

    assert config.host == "127.0.0.1"
    assert config.ip == {127, 0, 0, 1}
    assert config.port == 4001
    assert config.token == "daemon-token"
    assert config.owner == "control-plane-a"
    assert config.tenant_id == "tenant-a"
    assert config.session_ledger_path == Path.expand("tmp/session-ledger.json")
    assert config.worker_id == "worker-a"
    assert config.daemon_instance_id == "daemon-a"
    assert config.worker_profile_version == "profile-v1"
    assert config.workspace_roots == [root]
    assert config.max_sessions == 4
    assert config.max_sessions_per_tenant == nil
    assert config.rate_limit_window_ms == 60_000
    assert config.unauthenticated_rate_limit == 120
    assert config.api_rate_limit == 600
    assert config.session_create_rate_limit == 60
    assert [%{"path" => ^elixir}] = config.allowed_executables
    refute config.allow_any_executable?
    refute config.allow_unauthenticated?
    refute config.enable_dynamic_tool_bridge_proxy?
    assert config.allowed_dynamic_tool_bridge_upstreams == []
    refute config.allow_private_dynamic_tool_bridge_upstreams?
  end

  test "normalizes explicit Dynamic Tool bridge proxy policy" do
    root = Path.expand("tmp/worker-daemon-config")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")
    upstream = "HTTP://127.0.0.1:4521/api/v1/agent-tools/dynamic/"

    assert {:ok, %Config{} = config} =
             Config.normalize_cli_options(
               [
                 workspace_root: root,
                 allow_executable: elixir,
                 token: "daemon-token",
                 allow_dynamic_tool_bridge_upstream: upstream,
                 allow_private_dynamic_tool_bridge_upstream: true
               ],
               deps(root)
             )

    assert config.enable_dynamic_tool_bridge_proxy?
    assert config.allowed_dynamic_tool_bridge_upstreams == ["http://127.0.0.1:4521/api/v1/agent-tools/dynamic"]
    assert config.allow_private_dynamic_tool_bridge_upstreams?
  end

  test "server opts preserve normalized config fields" do
    config = %Config{
      host: "127.0.0.1",
      ip: {127, 0, 0, 1},
      port: 4101,
      token: "daemon-token",
      worker_id: "worker-a",
      daemon_instance_id: "daemon-a",
      worker_profile_version: "profile-v1",
      workspace_roots: ["/work"],
      max_sessions: 2,
      max_sessions_per_tenant: 1,
      rate_limit_window_ms: 30_000,
      unauthenticated_rate_limit: 20,
      api_rate_limit: 200,
      session_create_rate_limit: 10,
      allow_shell?: true,
      allowed_executables: [%{"command" => "elixir", "name" => "elixir", "path" => "/usr/bin/elixir"}],
      allow_any_executable?: false
    }

    opts = Config.to_server_opts(config)

    assert Keyword.fetch!(opts, :worker_id) == "worker-a"
    assert Keyword.fetch!(opts, :worker_profile_version) == "profile-v1"
    assert Keyword.fetch!(opts, :owner) == "symphony"
    assert Keyword.get(opts, :tenant_id) == nil
    assert Keyword.fetch!(opts, :workspace_roots) == ["/work"]
    assert Keyword.fetch!(opts, :max_sessions_per_tenant) == 1
    assert Keyword.fetch!(opts, :rate_limit_window_ms) == 30_000
    assert Keyword.fetch!(opts, :unauthenticated_rate_limit) == 20
    assert Keyword.fetch!(opts, :api_rate_limit) == 200
    assert Keyword.fetch!(opts, :session_create_rate_limit) == 10
    assert Keyword.fetch!(opts, :allowed_executables) == [%{"command" => "elixir", "name" => "elixir", "path" => "/usr/bin/elixir"}]
    assert Keyword.fetch!(opts, :allow_shell?)
    refute Keyword.fetch!(opts, :allow_unauthenticated?)
    refute Keyword.fetch!(opts, :enable_dynamic_tool_bridge_proxy?)
    assert Keyword.fetch!(opts, :allowed_dynamic_tool_bridge_upstreams) == []
    refute Keyword.fetch!(opts, :allow_private_dynamic_tool_bridge_upstreams?)
  end

  defp deps(root) do
    %{
      dir?: fn ^root -> true end,
      canonicalize: fn ^root -> {:ok, root} end,
      getenv: fn _name -> nil end,
      hostname: fn -> {:ok, "worker-host"} end,
      uuid: fn -> "daemon-uuid" end
    }
  end
end
