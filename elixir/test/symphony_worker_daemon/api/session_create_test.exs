defmodule SymphonyWorkerDaemon.Api.SessionCreateTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias SymphonyWorkerDaemon.Api.SessionCreate

  test "maps unsupported protocol versions to upgrade-required responses" do
    conn =
      conn(:post, "/api/v1/worker-daemon/sessions")
      |> SessionCreate.error(%{}, %{}, {:unsupported_protocol_version, "expected", "actual"})

    assert conn.status == 426
    assert Jason.decode!(conn.resp_body)["code"] == "unsupported_protocol_version"
  end

  test "maps denied create requests to forbidden responses" do
    request = %{"request_id" => "request-1", "caller" => %{"owner" => "owner-a"}}

    conn =
      conn(:post, "/api/v1/worker-daemon/sessions")
      |> SessionCreate.error(%{owner: "owner-a"}, request, :session_forbidden)

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["code"] == "session_forbidden"
  end

  test "maps capacity pressure to retryable responses" do
    conn =
      conn(:post, "/api/v1/worker-daemon/sessions")
      |> SessionCreate.error(%{}, %{}, :worker_full)

    assert conn.status == 429
    assert %{"code" => "worker_full", "retryable" => true} = Jason.decode!(conn.resp_body)
  end

  test "maps dynamic tool bridge validation failures to create rejection responses" do
    conn =
      conn(:post, "/api/v1/worker-daemon/sessions")
      |> SessionCreate.error(%{}, %{}, {:dynamic_tool_bridge_upstream_not_allowlisted, "https://example.invalid"})

    assert conn.status == 422
    assert Jason.decode!(conn.resp_body)["code"] == "dynamic_tool_bridge_rejected"
  end
end
