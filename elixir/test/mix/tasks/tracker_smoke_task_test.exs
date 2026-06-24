defmodule Mix.Tasks.Tracker.SmokeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Tracker.Smoke, as: TrackerSmokeTask
  alias SymphonyElixir.Workflow.Template, as: TemplateRegistry

  setup do
    Mix.Task.reenable("tracker.smoke")
    previous_workflow_path = Application.fetch_env(:symphony_elixir, :workflow_file_path)

    on_exit(fn ->
      restore_workflow_path(previous_workflow_path)
      Application.delete_env(:symphony_elixir, :memory_tracker_issue_state_overrides)
      Application.delete_env(:symphony_elixir, :memory_tracker_recipient)
      Mix.Task.reenable("tracker.smoke")
    end)

    :ok
  end

  test "prints help" do
    output = capture_io(fn -> TrackerSmokeTask.run(["--help"]) end)

    assert output =~ "mix tracker.smoke"
    assert output =~ "--confirm-state-write"
    assert output =~ "--template <alias>"
  end

  test "runs read-only tracker smoke for a bundled memory template" do
    output =
      capture_io(fn ->
        TrackerSmokeTask.run(["--template", TemplateRegistry.local_quickstart_alias(), "--json"])
      end)

    payload = Jason.decode!(output)

    assert payload["ok"] == true
    assert payload["tracker_kind"] == "memory"
    assert payload["smoke_mode"] == "read_only"
    assert payload["probe_count"] == 2
    assert payload["passed_count"] == 2
    assert Enum.map(payload["probes"], & &1["id"]) == ["config-validation", "healthcheck"]
  end

  test "fetches one targeted issue when issue id is supplied" do
    output =
      capture_io(fn ->
        TrackerSmokeTask.run(["--template", TemplateRegistry.local_quickstart_alias(), "--issue", "local-memory-1", "--json"])
      end)

    payload = Jason.decode!(output)

    assert payload["ok"] == true
    assert payload["probe_count"] == 3
    assert Enum.map(payload["probes"], & &1["id"]) == ["config-validation", "healthcheck", "fetch-issue"]
    assert Enum.find(payload["probes"], &(&1["id"] == "fetch-issue"))["summary"] =~ "current_state=classifying"
  end

  test "state-write mode writes the fetched current state with a precondition" do
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

    output =
      capture_io(fn ->
        TrackerSmokeTask.run([
          "--template",
          TemplateRegistry.local_quickstart_alias(),
          "--issue",
          "local-memory-1",
          "--confirm-state-write",
          "--json"
        ])
      end)

    payload = Jason.decode!(output)

    assert payload["ok"] == true
    assert payload["smoke_mode"] == "state_write"

    assert Enum.map(payload["probes"], & &1["id"]) == [
             "config-validation",
             "healthcheck",
             "fetch-issue",
             "state-write"
           ]

    assert Enum.find(payload["probes"], &(&1["id"] == "state-write"))["summary"] ==
             "state write accepted target=classifying expected_current_state=classifying"

    assert_receive {:memory_tracker_state_update, "local-memory-1", "classifying"}
  end

  test "rejects write-state without explicit state-write confirmation" do
    assert_raise Mix.Error, ~r/--write-state requires --confirm-state-write/, fn ->
      capture_io(fn ->
        TrackerSmokeTask.run([
          "--template",
          TemplateRegistry.local_quickstart_alias(),
          "--issue",
          "local-memory-1",
          "--write-state",
          "routed"
        ])
      end)
    end
  end

  defp restore_workflow_path({:ok, path}), do: Application.put_env(:symphony_elixir, :workflow_file_path, path)
  defp restore_workflow_path(:error), do: Application.delete_env(:symphony_elixir, :workflow_file_path)
end
