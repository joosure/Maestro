defmodule SymphonyWorkerDaemon.CLI.ArgumentsTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.CLI.Arguments

  test "parses daemon switches" do
    assert {:ok, opts} =
             Arguments.parse([
               "--workspace-root",
               "/work",
               "--port",
               "4101",
               "--token",
               "daemon-token",
               "--allow-any-executable",
               "--allow-dynamic-tool-bridge-upstream",
               "https://tools.example/api"
             ])

    assert Keyword.fetch!(opts, :workspace_root) == "/work"
    assert Keyword.fetch!(opts, :port) == 4101
    assert Keyword.fetch!(opts, :token) == "daemon-token"
    assert Keyword.fetch!(opts, :allow_any_executable)
    assert Keyword.fetch!(opts, :allow_dynamic_tool_bridge_upstream) == "https://tools.example/api"
  end

  test "reports invalid switches and unexpected positional arguments" do
    assert {:error, invalid_message} = Arguments.parse(["--unknown"])
    assert invalid_message =~ "Invalid worker daemon option"
    assert invalid_message =~ "Usage:"

    assert {:error, usage_message} = Arguments.parse(["positional"])
    assert usage_message == Arguments.usage_message()
  end
end
