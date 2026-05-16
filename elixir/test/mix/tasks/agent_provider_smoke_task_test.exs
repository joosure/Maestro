defmodule Mix.Tasks.AgentProvider.SmokeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.AgentProvider.Smoke, as: AgentProviderSmokeTask

  setup do
    Mix.Task.reenable("agent_provider.smoke")
    previous_workflow_path = Application.fetch_env(:symphony_elixir, :workflow_file_path)

    on_exit(fn ->
      restore_workflow_path(previous_workflow_path)
      Mix.Task.reenable("agent_provider.smoke")
    end)

    :ok
  end

  test "prints help" do
    output = capture_io(fn -> AgentProviderSmokeTask.run(["--help"]) end)

    assert output =~ "mix agent_provider.smoke"
    assert output =~ "--template <alias>"
    assert output =~ "--start-only"
  end

  test "runs agent-provider smoke for a bundled memory/mock template" do
    output =
      capture_io(fn ->
        AgentProviderSmokeTask.run(["--template", "memory/no_repo/mock", "--json"])
      end)

    payload = Jason.decode!(output)

    assert payload["ok"] == true
    assert payload["agent_provider_kind"] == "mock"
    assert payload["smoke_mode"] == "first_turn"
    assert payload["workspace"] == "temporary"

    assert Enum.map(payload["probes"], & &1["id"]) == [
             "config-validation",
             "capability",
             "workspace",
             "prepare-workspace",
             "start-session",
             "run-turn",
             "stop-session",
             "cleanup"
           ]
  end

  test "rejects workflow and template together" do
    assert_raise Mix.Error, ~r/Pass either --workflow or --template/, fn ->
      capture_io(fn ->
        AgentProviderSmokeTask.run(["--workflow", "WORKFLOW.md", "--template", "memory/no_repo/mock"])
      end)
    end
  end

  defp restore_workflow_path({:ok, path}), do: Application.put_env(:symphony_elixir, :workflow_file_path, path)
  defp restore_workflow_path(:error), do: Application.delete_env(:symphony_elixir, :workflow_file_path)
end
