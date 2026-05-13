defmodule SymphonyWorkerDaemon.Protocol.RequestTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Protocol.Request

  test "input builds protocol input payloads" do
    assert Request.input(["hel", "lo"], [request_id: :request_input], "version-1") == %{
             "protocol_version" => "version-1",
             "request_id" => "request_input",
             "input" => "hello",
             "encoding" => "utf-8"
           }
  end

  test "stop builds idempotent stop payloads" do
    assert Request.stop([request_id: "request-stop", reason: :operator_stop], "version-1") == %{
             "protocol_version" => "version-1",
             "request_id" => "request-stop",
             "idempotency_key" => "request-stop",
             "reason" => "operator_stop"
           }

    assert Request.stop([request_id: "request-stop", idempotency_key: "idem-stop"], "version-1")[
             "idempotency_key"
           ] == "idem-stop"
  end

  test "cleanup builds idempotent cleanup payloads" do
    assert Request.cleanup([request_id: 123], "version-1") == %{
             "protocol_version" => "version-1",
             "request_id" => "123",
             "idempotency_key" => "123"
           }
  end
end
