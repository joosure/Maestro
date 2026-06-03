defmodule SymphonyElixir.Agent.Runtime.DynamicToolBridgeTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.DynamicTool.{Bridge, BridgeContract, BridgeRegistry}
  alias SymphonyElixir.Agent.Runtime.{DynamicToolBridge, Target}

  setup do
    ensure_named_process!(BridgeRegistry)

    previous_token = Application.get_env(:symphony_elixir, BridgeContract.token_config_key())
    Application.put_env(:symphony_elixir, BridgeContract.token_config_key(), "test-bridge-token")

    on_exit(fn ->
      restore_application_env(BridgeContract.token_config_key(), previous_token)
    end)

    :ok
  end

  test "runtime_env/1 exposes local loopback bridge env for local provider processes" do
    assert {:ok, runtime} = DynamicToolBridge.start(http_port: 4521, tool_context: tool_context())
    assert {:ok, env} = DynamicToolBridge.runtime_env(dynamic_tool_bridge_runtime: runtime)

    token = env[BridgeContract.token_env()]

    try do
      assert env[BridgeContract.base_url_env()] == "http://127.0.0.1:4521#{BridgeContract.base_path()}"
      assert is_binary(token)
      assert token != "test-bridge-token"
      assert Bridge.valid_token?(token)
      assert env[BridgeContract.transport_env()] == BridgeContract.local_transport()
    after
      DynamicToolBridge.stop(runtime)
    end
  end

  test "runtime_env/1 defaults SSH worker processes to tunnel loopback env" do
    assert {:ok, runtime} =
             DynamicToolBridge.start(
               http_port: 4521,
               worker_host: "worker.example",
               dynamic_tool_bridge_remote_port: 19_421,
               dynamic_tool_bridge_ssh_forwarder: fn _worker_host, _remote_port, _local_host, _local_port, _forward_opts ->
                 {:ok, :fake_tunnel}
               end,
               tool_context: tool_context()
             )

    assert {:ok, env} = DynamicToolBridge.runtime_env(dynamic_tool_bridge_runtime: runtime)

    token = env[BridgeContract.token_env()]

    try do
      assert env[BridgeContract.base_url_env()] == "http://127.0.0.1:19421#{BridgeContract.base_path()}"
      assert is_binary(token)
      assert token != "test-bridge-token"
      assert Bridge.valid_token?(token)
      assert env[BridgeContract.transport_env()] == BridgeContract.ssh_tunnel_transport()
    after
      DynamicToolBridge.stop(runtime)
    end
  end

  test "start/1 starts an SSH remote port forward before returning runtime metadata" do
    owner = self()

    forwarder = fn worker_host, remote_port, local_host, local_port, forward_opts ->
      send(owner, {:forwarder_called, worker_host, remote_port, local_host, local_port, forward_opts})
      {:ok, :fake_tunnel}
    end

    assert {:ok, runtime} =
             DynamicToolBridge.start(
               http_port: 4521,
               worker_host: "worker.example",
               dynamic_tool_bridge_remote_port: "19421",
               dynamic_tool_bridge_ssh_forwarder: forwarder,
               dynamic_tool_bridge_ssh_forward_opts: [connect_timeout_ms: 500],
               tool_context: tool_context()
             )

    assert_receive {:forwarder_called, "worker.example", 19_421, "127.0.0.1", 4521, [connect_timeout_ms: 500]}
    assert runtime.transport == :ssh_tunnel_http
    assert runtime.remote_port == 19_421
    assert runtime.worker_host == "worker.example"

    assert %{
             dynamic_tool_bridge_transport: "ssh_tunnel_http",
             dynamic_tool_bridge_base_url: "http://127.0.0.1:19421/api/v1/agent-tools/dynamic",
             dynamic_tool_bridge_local_port: 4521,
             dynamic_tool_bridge_remote_port: 19_421,
             dynamic_tool_bridge_worker_host: "worker.example"
           } = DynamicToolBridge.metadata(runtime)

    DynamicToolBridge.stop(runtime)
  end

  test "transport override is rejected because bridge transport is derived from runtime target" do
    assert {:error, {:unsupported_dynamic_tool_bridge_option, :dynamic_tool_bridge_transport}} =
             DynamicToolBridge.start(
               http_port: 4521,
               worker_host: "worker.example",
               dynamic_tool_bridge_transport: "private_http",
               tool_context: tool_context()
             )
  end

  test "unsupported host override is rejected instead of widening local_http reachability" do
    assert {:error, {:unsupported_dynamic_tool_bridge_option, :dynamic_tool_bridge_host}} =
             DynamicToolBridge.start(
               http_port: 4521,
               dynamic_tool_bridge_host: "0.0.0.0",
               tool_context: tool_context()
             )
  end

  test "runtime_env/1 requires managed runtime for non-empty session tool contexts" do
    assert {:error, :dynamic_tool_bridge_runtime_required} =
             DynamicToolBridge.runtime_env(http_port: 4521, tool_context: tool_context())
  end

  test "sessions without dynamic tools do not emit bridge env or start an SSH tunnel" do
    owner = self()

    forwarder = fn worker_host, remote_port, local_host, local_port, forward_opts ->
      send(owner, {:unexpected_forwarder_called, worker_host, remote_port, local_host, local_port, forward_opts})
      {:ok, :fake_tunnel}
    end

    assert {:ok, runtime} =
             DynamicToolBridge.start(
               worker_host: "worker.example",
               dynamic_tool_bridge_ssh_forwarder: forwarder,
               tool_context: empty_tool_context()
             )

    assert runtime == %{enabled?: false, env: %{}, transport: :ssh_tunnel_http, tunnel: nil}
    refute_received {:unexpected_forwarder_called, _, _, _, _, _}

    assert {:ok, %{}} = DynamicToolBridge.runtime_env(worker_host: "worker.example", tool_context: empty_tool_context())
  end

  test "worker daemon sessions without dynamic tools do not need bridge env" do
    target = Target.new(placement: :worker_daemon, workspace_path: "/tmp/work", metadata: %{worker_daemon_endpoint: "http://daemon"})

    assert {:ok, runtime} = DynamicToolBridge.start(agent_runtime_target: target, tool_context: empty_tool_context())
    assert runtime == %{enabled?: false, env: %{}, transport: :worker_daemon_http, tunnel: nil}
  end

  test "worker daemon dynamic-tool bridge returns daemon proxy spec instead of provider env" do
    target = Target.new(placement: :worker_daemon, workspace_path: "/tmp/work", metadata: %{worker_daemon_endpoint: "http://daemon"})

    assert {:ok, runtime} =
             DynamicToolBridge.start(http_port: 4521, agent_runtime_target: target, tool_context: tool_context())

    assert runtime.enabled?
    assert runtime.transport == :worker_daemon_http
    assert runtime.env == %{}
    assert runtime.daemon_bridge["transport"] == BridgeContract.worker_daemon_transport()
    assert runtime.daemon_bridge["symphony_base_url"] == "http://127.0.0.1:4521#{BridgeContract.base_path()}"
    assert runtime.daemon_bridge["provider_env"][BridgeContract.transport_env()] == BridgeContract.worker_daemon_transport()

    DynamicToolBridge.stop(runtime)
  end

  test "local bridge fails fast when dynamic tools require an unavailable Symphony HTTP bridge port" do
    assert {:error, :dynamic_tool_bridge_http_port_unavailable} =
             DynamicToolBridge.start(tool_context: tool_context())
  end

  defp restore_application_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_application_env(key, value), do: Application.put_env(:symphony_elixir, key, value)

  defp tool_context do
    %{
      source_context: %{},
      tool_specs: [
        %{
          "name" => "fake_tool",
          "description" => "Fake dynamic tool.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      tool_environment: %{}
    }
  end

  defp empty_tool_context do
    %{source_context: %{}, tool_specs: [], tool_environment: %{}}
  end

  defp ensure_named_process!(module) do
    case Process.whereis(module) do
      pid when is_pid(pid) -> :ok
      nil -> start_supervised!(module)
    end
  end
end
