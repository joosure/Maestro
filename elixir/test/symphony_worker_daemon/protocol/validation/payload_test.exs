defmodule SymphonyWorkerDaemon.Protocol.Validation.PayloadTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Protocol.Validation.Payload

  test "size accepts payloads within configured limits" do
    assert Payload.size("input", "hello", 5) == :ok
    assert Payload.size("request", %{"ok" => true}, 16) == :ok
    assert Payload.size("request", %{"ok" => true}, nil) == :ok
  end

  test "size rejects oversized and invalid payloads" do
    assert Payload.size("input", "hello", 4) == {:error, {:payload_too_large, "input", 5, 4}}
    assert Payload.size("request", self(), 128) == {:error, {:payload_invalid, "request"}}
  end

  test "limit resolves configured positive limits" do
    assert Payload.limit([max_bytes: 10], :max_bytes, 5) == 10
    assert Payload.limit([max_bytes: :infinity], :max_bytes, 5) == nil
    assert Payload.limit([max_bytes: 0], :max_bytes, 5) == 5
    assert Payload.limit([], :max_bytes, 5) == 5
  end

  test "string_list normalizes string-like values" do
    assert Payload.string_list([" create ", :input, 3, "", nil, %{}]) == ["create", "input", "3"]
  end
end
