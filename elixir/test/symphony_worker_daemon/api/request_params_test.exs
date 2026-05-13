defmodule SymphonyWorkerDaemon.Api.RequestParamsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias SymphonyWorkerDaemon.Api.RequestParams

  test "body_params returns parsed body maps only" do
    assert RequestParams.body_params(%Plug.Conn{body_params: %{"request_id" => "request-1"}}) == %{
             "request_id" => "request-1"
           }

    assert RequestParams.body_params(conn(:post, "/api/v1/worker-daemon/sessions", "raw")) == %{}
  end

  test "session_filters keeps only supported session query keys" do
    assert RequestParams.session_filters(%{
             "owner" => "owner-a",
             "tenant_id" => "tenant-a",
             "run_id" => "run-1",
             "status" => "running",
             "ignored" => "value"
           }) == %{
             "owner" => "owner-a",
             "tenant_id" => "tenant-a",
             "run_id" => "run-1",
             "status" => "running"
           }
  end

  test "event_filters returns event options as keyword input" do
    assert RequestParams.event_filters(%{"after_event_id" => "12", "limit" => "20", "ignored" => "value"}) == [
             after_event_id: "12",
             limit: "20"
           ]
  end

  test "protocol_limit_opts projects configured protocol limits" do
    assert RequestParams.protocol_limit_opts(
             max_protocol_request_bytes: 1,
             max_protocol_caller_bytes: 2,
             max_protocol_command_bytes: 3,
             max_protocol_env_bytes: 4,
             max_protocol_dynamic_tool_bridge_bytes: 5,
             max_protocol_input_bytes: 6
           ) == [
             max_protocol_request_bytes: 1,
             max_protocol_caller_bytes: 2,
             max_protocol_command_bytes: 3,
             max_protocol_env_bytes: 4,
             max_protocol_dynamic_tool_bridge_bytes: 5,
             max_protocol_input_bytes: 6
           ]
  end
end
