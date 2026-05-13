defmodule SymphonyWorkerDaemon.BridgeProxyTest do
  use ExUnit.Case, async: false

  alias SymphonyWorkerDaemon.{BridgeProxy, CapacityManager}
  alias SymphonyWorkerDaemon.Session

  @base_url_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"
  @token_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN"
  @transport_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT"
  @upstream_base_url "http://127.0.0.1:4521/api/v1/agent-tools/dynamic"

  defmodule EnvCaptureRunner do
    def start(_command, _cwd, env, opts) do
      send(Keyword.fetch!(opts, :owner), {:provider_env, env})
      {:ok, :fake_provider_handle}
    end

    def stop(_handle, _opts), do: :ok
  end

  test "bridge proxy exposes worker-loopback env and forwards with upstream token" do
    owner = self()

    requester = fn :post, "http://127.0.0.1:4521/api/v1/agent-tools/dynamic/execute", headers, body, %{timeout_ms: 30_000} ->
      send(owner, {:upstream_request, headers, body})
      {:ok, 200, %{"success" => true, "payload" => %{"ok" => true}}}
    end

    assert {:ok, proxy} =
             BridgeProxy.start_from_request(
               %{
                 "dynamic_tool_bridge" => %{
                   "symphony_base_url" => @upstream_base_url,
                   "token" => "symphony-token"
                 }
               },
               bridge_proxy_opts(@upstream_base_url,
                 session_token: "session-token",
                 bridge_proxy_requester: requester
               )
             )

    assert proxy.env[@token_env] == "session-token"
    assert proxy.env[@transport_env] == "worker_daemon_http"
    assert proxy.env[@base_url_env] =~ "http://127.0.0.1:"

    assert {:ok, %Req.Response{status: 200, body: body}} =
             Req.post(proxy.env[@base_url_env] <> "/execute",
               headers: [{"authorization", "Bearer session-token"}],
               json: %{"tool" => "fake_tool", "arguments" => %{"id" => "1"}}
             )

    assert body == %{"success" => true, "payload" => %{"ok" => true}}

    assert_receive {:upstream_request, headers, %{"tool" => "fake_tool", "arguments" => %{"id" => "1"}}}
    assert {"authorization", "Bearer symphony-token"} in headers

    assert :ok = BridgeProxy.stop(proxy)
  end

  test "bridge proxy rejects provider requests with invalid session token" do
    requester = fn _method, _url, _headers, _body, _request_opts ->
      flunk("unauthorized provider request must not reach upstream")
    end

    assert {:ok, proxy} =
             BridgeProxy.start_from_request(
               %{
                 "dynamic_tool_bridge" => %{
                   "symphony_base_url" => @upstream_base_url,
                   "token" => "symphony-token"
                 }
               },
               bridge_proxy_opts(@upstream_base_url,
                 session_token: "session-token",
                 bridge_proxy_requester: requester
               )
             )

    assert {:ok, %Req.Response{status: 401, body: body}} =
             Req.post(proxy.env[@base_url_env] <> "/execute",
               headers: [{"authorization", "Bearer wrong-token"}],
               json: %{"tool" => "fake_tool", "arguments" => %{}}
             )

    assert get_in(body, ["payload", "error", "code"]) == "dynamic_tool_bridge_proxy_unauthorized"
    assert :ok = BridgeProxy.stop(proxy)
  end

  test "bridge proxy is disabled unless the daemon explicitly enables it" do
    assert {:error, :dynamic_tool_bridge_proxy_disabled} =
             BridgeProxy.start_from_request(%{
               "dynamic_tool_bridge" => %{
                 "symphony_base_url" => @upstream_base_url,
                 "token" => "symphony-token"
               }
             })
  end

  test "bridge proxy rejects unsafe upstream bridge URLs before provider env injection" do
    assert {:error, :dynamic_tool_bridge_upstream_base_url_invalid} =
             BridgeProxy.start_from_request(
               %{
                 "dynamic_tool_bridge" => %{
                   "symphony_base_url" => "http://user:secret@127.0.0.1:4521/api/v1/agent-tools/dynamic?token=secret",
                   "token" => "symphony-token"
                 }
               },
               enable_dynamic_tool_bridge_proxy?: true,
               allowed_dynamic_tool_bridge_upstreams: [@upstream_base_url]
             )
  end

  test "bridge proxy rejects upstreams outside the daemon allowlist" do
    assert {:error, {:dynamic_tool_bridge_upstream_not_allowlisted, @upstream_base_url}} =
             BridgeProxy.start_from_request(
               %{
                 "dynamic_tool_bridge" => %{
                   "symphony_base_url" => @upstream_base_url,
                   "token" => "symphony-token"
                 }
               },
               enable_dynamic_tool_bridge_proxy?: true,
               allowed_dynamic_tool_bridge_upstreams: ["https://tools.example.com/api/v1/agent-tools/dynamic"]
             )
  end

  test "bridge proxy rejects private upstream addresses unless explicitly allowed" do
    assert {:error, {:dynamic_tool_bridge_upstream_address_blocked, "127.0.0.1", {127, 0, 0, 1}, :loopback}} =
             BridgeProxy.start_from_request(
               %{
                 "dynamic_tool_bridge" => %{
                   "symphony_base_url" => @upstream_base_url,
                   "token" => "symphony-token"
                 }
               },
               enable_dynamic_tool_bridge_proxy?: true,
               allowed_dynamic_tool_bridge_upstreams: [@upstream_base_url]
             )
  end

  test "session server injects daemon bridge env into provider process" do
    %{registry: registry, capacity: capacity, supervisor: supervisor} = start_daemon_core!()
    workspace = tmp_dir!("bridge-env")

    request =
      session_request(workspace)
      |> Map.put("dynamic_tool_bridge", %{
        "symphony_base_url" => @upstream_base_url,
        "token" => "symphony-token"
      })

    assert {:ok, pid, %{"status" => "running"}} =
             Session.Supervisor.start_session(supervisor, request,
               registry: registry,
               capacity_manager: capacity,
               workspace_roots: [workspace],
               allow_any_executable?: true,
               process_runner: EnvCaptureRunner,
               process_runner_opts: [owner: self()],
               dynamic_tool_bridge_session_token: "session-token",
               bridge_proxy_requester: fn _method, _url, _headers, _body, _opts -> {:ok, 200, %{}} end,
               enable_dynamic_tool_bridge_proxy?: true,
               allowed_dynamic_tool_bridge_upstreams: [@upstream_base_url],
               allow_private_dynamic_tool_bridge_upstreams?: true
             )

    assert_receive {:provider_env, env}
    assert env[@token_env] == "session-token"
    assert env[@transport_env] == "worker_daemon_http"
    assert env[@base_url_env] =~ "http://127.0.0.1:"

    assert %{"dynamic_tool_bridge" => %{"base_url" => base_url, "port" => port}} = Session.Server.status(pid)
    assert base_url == env[@base_url_env]
    assert is_integer(port)
  end

  defp start_daemon_core! do
    registry = __MODULE__.Registry
    capacity = __MODULE__.Capacity
    supervisor = __MODULE__.SessionSupervisor

    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})
    start_supervised!({Session.Supervisor, name: supervisor})

    %{registry: registry, capacity: capacity, supervisor: supervisor}
  end

  defp session_request(workspace) do
    %{
      "protocol_version" => SymphonyWorkerDaemon.Protocol.protocol_version(),
      "request_id" => "request-1",
      "session_id" => "session-bridge",
      "run_id" => "run-1",
      "caller" => %{"provider_kind" => "fake", "worker_pool" => "coding-linux"},
      "command" => %{"mode" => "argv", "argv" => ["fake"]},
      "workspace" => %{"cwd" => workspace},
      "env" => %{"EXISTING_ENV" => "kept"}
    }
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-worker-daemon-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp bridge_proxy_opts(upstream_base_url, opts) do
    opts
    |> Keyword.put(:enable_dynamic_tool_bridge_proxy?, true)
    |> Keyword.put(:allowed_dynamic_tool_bridge_upstreams, [upstream_base_url])
    |> Keyword.put(:allow_private_dynamic_tool_bridge_upstreams?, true)
  end
end
