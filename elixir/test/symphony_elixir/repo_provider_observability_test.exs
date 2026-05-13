defmodule SymphonyElixir.RepoProviderObservabilityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.CLI.RepoProvider, as: RepoProviderCLI
  alias SymphonyElixir.Observability.EventStore

  setup do
    {:ok, _apps} = Application.ensure_all_started(:symphony_elixir)

    EventStore.configure_from_observability(%{})
    EventStore.reset()

    on_exit(fn ->
      EventStore.configure_from_observability(%{})
      EventStore.reset()
    end)

    :ok
  end

  test "repo-provider emits started and finished observability events for successful commands" do
    deps =
      cli_deps(%{
        "SYMPHONY_REPO_PROVIDER_KIND" => "github"
      })

    capture_log(fn ->
      assert {"cnb\n", "", 0} = RepoProviderCLI.evaluate(["--provider", "cnb", "current-kind"], deps)
    end)

    [finished, started] = wait_for_recent_events("current-kind", 2)

    assert started["event"] == "repo_provider_command_started"
    assert started["component"] == "repo_provider.cli"
    assert started["operation_name"] == "current-kind"
    assert started["provider_kind"] == "cnb"
    assert started["repo_provider_runtime"] == "symphony"
    assert started["retry_count"] == 0

    assert finished["event"] == "repo_provider_command_finished"
    assert finished["component"] == "repo_provider.cli"
    assert finished["operation_name"] == "current-kind"
    assert finished["provider_kind"] == "cnb"
    assert finished["repo_provider_runtime"] == "symphony"
    assert finished["exit_code"] == 0
    refute Map.has_key?(finished, "error_code")
  end

  test "repo-provider finished observability events capture error metadata" do
    deps =
      cli_deps(%{
        "SYMPHONY_REPO_PROVIDER_KIND" => "github"
      })

    with_env(%{"PATH" => ""}, fn ->
      capture_log(fn ->
        assert {"", "GitHub provider requires gh in PATH\n", 64} = RepoProviderCLI.evaluate(["auth-status"], deps)
      end)
    end)

    [finished, started] = wait_for_recent_events("auth-status", 2)

    assert started["event"] == "repo_provider_command_started"
    assert started["operation_name"] == "auth-status"
    assert started["provider_kind"] == "github"
    assert started["repo_provider_runtime"] == "symphony"

    assert finished["event"] == "repo_provider_command_finished"
    assert finished["operation_name"] == "auth-status"
    assert finished["provider_kind"] == "github"
    assert finished["repo_provider_runtime"] == "symphony"
    assert finished["exit_code"] == 64
    assert finished["error_code"] == "missing_tooling"
    assert finished["error"] == "GitHub provider requires gh in PATH"
  end

  defp wait_for_recent_events(operation_name, expected_count, attempts \\ 200)

  defp wait_for_recent_events(operation_name, expected_count, attempts)
       when is_binary(operation_name) and is_integer(expected_count) and is_integer(attempts) and attempts > 0 do
    events =
      EventStore.recent_events(limit: 50)
      |> Enum.filter(fn event ->
        event["component"] == "repo_provider.cli" and event["operation_name"] == operation_name
      end)

    if length(events) >= expected_count do
      Enum.take(events, expected_count)
    else
      Process.sleep(20)
      wait_for_recent_events(operation_name, expected_count, attempts - 1)
    end
  end

  defp wait_for_recent_events(operation_name, expected_count, _attempts) do
    flunk("Expected #{expected_count} repo-provider observability events for #{operation_name}")
  end

  defp cli_deps(env, extra \\ []) do
    %{
      env: fn -> env end,
      stdout: fn _output -> :ok end,
      stderr: fn _output -> :ok end,
      halt: fn _status -> raise "halt should not be called from evaluate/2" end
    }
    |> Map.merge(Map.new(extra))
  end

  defp with_env(overrides, fun) do
    keys = Map.keys(overrides)
    previous = Map.new(keys, fn key -> {key, System.get_env(key)} end)

    try do
      Enum.each(overrides, fn {key, value} -> System.put_env(key, value) end)
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
