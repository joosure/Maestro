defmodule SymphonyWorkerDaemon.Config.ListenAddressTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Config.ListenAddress

  test "resolves default, localhost, and IPv6 addresses" do
    assert {:ok, "127.0.0.1", {127, 0, 0, 1}} = ListenAddress.resolve([], "127.0.0.1")
    assert {:ok, "localhost", {127, 0, 0, 1}} = ListenAddress.resolve([host: "localhost"], "127.0.0.1")
    assert {:ok, "::1", {0, 0, 0, 0, 0, 0, 0, 1}} = ListenAddress.resolve([host: "::1"], "127.0.0.1")
  end

  test "rejects invalid hosts with daemon context" do
    assert {:error, message} = ListenAddress.resolve([host: "not-a-host"], "127.0.0.1")
    assert message =~ "Invalid worker daemon host"
  end
end
