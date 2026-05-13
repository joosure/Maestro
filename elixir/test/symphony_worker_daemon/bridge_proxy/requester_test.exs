defmodule SymphonyWorkerDaemon.BridgeProxy.RequesterTest do
  use ExUnit.Case, async: false

  alias SymphonyWorkerDaemon.BridgeProxy.Requester

  defmodule CapturePlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = read_body(conn)

      send(Keyword.fetch!(opts, :owner), {
        :request,
        conn.method,
        conn.request_path,
        get_req_header(conn, "authorization"),
        get_req_header(conn, "content-type"),
        body
      })

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(202, Jason.encode!(%{"accepted" => true}))
    end
  end

  test "sends JSON body and returns upstream status and payload" do
    port = reserve_port!()
    start_supervised!({Bandit, plug: {CapturePlug, owner: self()}, scheme: :http, ip: {127, 0, 0, 1}, port: port})

    assert {:ok, 202, %{"accepted" => true}} =
             Requester.request(
               :post,
               "http://127.0.0.1:#{port}/execute",
               [{"authorization", "Bearer upstream-token"}],
               %{"tool" => "fake_tool"},
               %{timeout_ms: 5_000}
             )

    assert_receive {:request, "POST", "/execute", ["Bearer upstream-token"], [content_type], body}
    assert content_type =~ "application/json"
    assert Jason.decode!(body) == %{"tool" => "fake_tool"}
  end

  test "returns transport errors" do
    port = reserve_port!()

    assert {:error, %Req.TransportError{}} =
             Requester.request(:get, "http://127.0.0.1:#{port}/missing", [], nil, %{timeout_ms: 50})
  end

  test "rejects unsafe upstream request URLs before transport" do
    assert {:error, {:dynamic_tool_bridge_request_url_invalid, :scheme}} =
             Requester.request(:post, "ftp://tools.example.com/execute", [], %{}, %{})

    assert {:error, {:dynamic_tool_bridge_request_url_invalid, :userinfo}} =
             Requester.request(:post, "https://user:secret@tools.example.com/execute", [], %{}, %{})

    assert {:error, {:dynamic_tool_bridge_request_url_invalid, :query}} =
             Requester.request(:post, "https://tools.example.com/execute?token=secret", [], %{}, %{})
  end

  defp reserve_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
