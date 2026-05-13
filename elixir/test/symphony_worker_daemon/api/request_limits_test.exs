defmodule SymphonyWorkerDaemon.Api.RequestLimitsTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias SymphonyWorkerDaemon.Api.RequestLimits

  test "rejects headers over configured byte limit" do
    conn =
      conn(:get, "/api/v1/worker-daemon/health")
      |> put_req_header("x-large-header", String.duplicate("a", 20))
      |> assign(:worker_daemon_opts, max_header_bytes: 8)
      |> RequestLimits.reject_oversized_headers()

    assert conn.halted
    assert conn.status == 431
    assert Jason.decode!(conn.resp_body)["code"] == "headers_too_large"
  end

  test "keeps requests within configured header byte limit" do
    conn =
      conn(:get, "/api/v1/worker-daemon/health")
      |> assign(:worker_daemon_opts, max_header_bytes: 128)
      |> RequestLimits.reject_oversized_headers()

    refute conn.halted
    assert conn.status == nil
  end

  test "rejects content length over configured body byte limit" do
    conn =
      conn(:post, "/api/v1/worker-daemon/sessions", "{}")
      |> put_req_header("content-length", "9")
      |> assign(:worker_daemon_opts, max_request_body_bytes: 8)
      |> RequestLimits.reject_oversized_content_length()

    assert conn.halted
    assert conn.status == 413
    assert Jason.decode!(conn.resp_body)["code"] == "payload_too_large"
  end

  test "ignores malformed content length values" do
    conn =
      conn(:post, "/api/v1/worker-daemon/sessions", "{}")
      |> put_req_header("content-length", "invalid")
      |> assign(:worker_daemon_opts, max_request_body_bytes: 8)
      |> RequestLimits.reject_oversized_content_length()

    refute conn.halted
    assert conn.status == nil
  end
end
