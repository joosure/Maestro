defmodule SymphonyElixir.Agent.DynamicTool.BridgeControllerTest do
  use SymphonyElixir.TestSupport

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Platform.DynamicToolBridgeContract, as: BridgeContract

  @endpoint SymphonyElixirWeb.Endpoint

  defmodule FakeAdapter do
    @behaviour SymphonyElixir.Tracker.Adapter

    def kind, do: "fake_http"
    def defaults, do: %{}
    def validate_config(_tracker), do: :ok

    def dynamic_tools(_tracker) do
      [
        %{
          "name" => "fake_http_tool",
          "description" => "Fake HTTP bridge tool.",
          "inputSchema" => %{"type" => "object", "additionalProperties" => true},
          "capability" => "test.fake_http",
          "sideEffect" => "read_only"
        }
      ]
    end

    def execute_dynamic_tool(_tracker, tool, arguments, _opts) do
      {:success, %{"tool" => tool, "arguments" => arguments}}
    end
  end

  test "executes dynamic tools through the authenticated HTTP bridge" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{"fake_http" => FakeAdapter})
    Application.put_env(:symphony_elixir, BridgeContract.token_config_key(), "http-bridge-token")

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
      Application.delete_env(:symphony_elixir, BridgeContract.token_config_key())
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "fake_http",
      tracker_endpoint: nil,
      tracker_api_token: nil,
      tracker_api_secret: nil,
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil
    )

    start_test_endpoint()

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer http-bridge-token")
      |> post(BridgeContract.execute_path(), %{
        "tool" => "fake_http_tool",
        "arguments" => %{"identifier" => "HTTP-1"}
      })
      |> json_response(200)

    assert response == %{
             "success" => true,
             "payload" => %{"tool" => "fake_http_tool", "arguments" => %{"identifier" => "HTTP-1"}}
           }
  end

  test "records session-scoped runtime metadata for MCP bridge tool calls" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{"fake_http" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "fake_http",
      tracker_endpoint: nil,
      tracker_api_token: nil,
      tracker_api_secret: nil,
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil
    )

    EventStore.reset()
    start_test_endpoint()
    tool_context = Context.capture([])

    assert {:ok, runtime} =
             DynamicToolBridge.start(
               http_port: 4521,
               tool_context: tool_context,
               run_id: "run-http-bridge",
               issue_id: "issue-http-bridge",
               issue_identifier: "HTTP-42",
               agent_provider_kind: "codex"
             )

    try do
      token = Map.fetch!(runtime, :bridge_token)

      assert %{"success" => true} =
               build_conn()
               |> put_req_header("authorization", "Bearer #{token}")
               |> post(BridgeContract.execute_path(), %{
                 "tool" => "fake_http_tool",
                 "arguments" => %{"identifier" => "HTTP-42"}
               })
               |> json_response(200)

      event =
        EventStore.recent_issue_events(%{run_id: "run-http-bridge"}, limit: 10)
        |> Enum.find(&(&1["event"] == "tool_call_succeeded" and &1["tool_name"] == "fake_http_tool"))

      assert event["issue_id"] == "issue-http-bridge"
      assert event["issue_identifier"] == "HTTP-42"
      assert event["agent_provider_kind"] == "codex"
      assert event["dynamic_tool_usage_kind"] == "typed"
      assert event["dynamic_tool_capability"] == "test.fake_http"
    after
      DynamicToolBridge.stop(runtime)
    end
  end

  test "rejects unauthenticated dynamic tool bridge requests" do
    Application.put_env(:symphony_elixir, BridgeContract.token_config_key(), "http-bridge-token")

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, BridgeContract.token_config_key())
    end)

    start_test_endpoint()

    response =
      build_conn()
      |> post(BridgeContract.execute_path(), %{"tool" => "fake_http_tool", "arguments" => %{}})
      |> json_response(401)

    assert get_in(response, ["payload", "error", "message"]) =~ "Unauthorized"
  end

  test "rejects dynamic tool bridge requests from non-loopback clients" do
    Application.put_env(:symphony_elixir, BridgeContract.token_config_key(), "http-bridge-token")

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, BridgeContract.token_config_key())
    end)

    start_test_endpoint()

    response =
      %{build_conn() | remote_ip: {10, 0, 0, 12}}
      |> put_req_header("authorization", "Bearer http-bridge-token")
      |> post(BridgeContract.execute_path(), %{"tool" => "fake_http_tool", "arguments" => %{}})
      |> json_response(403)

    assert get_in(response, ["payload", "error", "message"]) =~ "loopback"
  end

  defp start_test_endpoint do
    endpoint_config =
      :symphony_elixir
      |> Application.get_env(SymphonyElixirWeb.Endpoint, [])
      |> Keyword.merge(server: false, secret_key_base: String.duplicate("s", 64))

    Application.put_env(:symphony_elixir, SymphonyElixirWeb.Endpoint, endpoint_config)
    start_supervised!({SymphonyElixirWeb.Endpoint, []})
  end
end
