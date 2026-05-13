defmodule Mix.Tasks.WorkerDaemon.Check do
  @moduledoc """
  Runs deterministic Worker Daemon production-readiness checks.
  """

  use Mix.Task

  @shortdoc "Run deterministic Worker Daemon validation checks"

  @test_paths [
    "test/symphony_worker_daemon/config_test.exs",
    "test/symphony_worker_daemon/cli_test.exs",
    "test/symphony_worker_daemon/server_test.exs",
    "test/symphony_worker_daemon/bridge_proxy_test.exs",
    "test/symphony_worker_daemon/provider_app_server_test.exs",
    "test/symphony_worker_daemon/simulated_provider_turn_test.exs",
    "test/symphony_elixir/agent/runtime/worker_daemon_test.exs",
    "test/symphony_elixir/agent/runtime/dynamic_tool_bridge_test.exs",
    "test/symphony_elixir/agent/credential/store_test.exs",
    "test/symphony_elixir/claude_code_credential_quota_test.exs",
    "test/symphony_elixir/agent/quota/poller_test.exs",
    "test/symphony_elixir/agent_provider_registry_test.exs"
  ]

  @impl true
  @spec run([String.t()]) :: :ok
  def run(_args) do
    Mix.Task.run("specs.check", [])
    Mix.Task.run("test", @test_paths)
  end
end
