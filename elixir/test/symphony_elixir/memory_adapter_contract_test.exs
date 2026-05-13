defmodule SymphonyElixir.MemoryAdapterContractTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Config
  alias SymphonyElixir.Tracker.Memory

  use SymphonyElixir.TrackerAdapterContract,
    adapter: SymphonyElixir.Tracker.Memory,
    config: %SymphonyElixir.Tracker.Config{
      kind: "memory",
      endpoint: nil,
      auth: %{},
      provider: %{},
      lifecycle: %{}
    }

  test "reads issues embedded in memory tracker provider config" do
    tracker = %Config{
      kind: "memory",
      provider: %{
        "issues" => [
          %{
            "id" => "local-1",
            "identifier" => "MEM-1",
            "title" => "Local memory issue",
            "description" => "Configured in the workflow template",
            "state" => "classifying",
            "labels" => ["local", "quick-start"]
          },
          %{"id" => "missing-required-fields"}
        ]
      },
      lifecycle: %{}
    }

    assert {:ok, [%Issue{} = issue]} = Memory.fetch_candidate_issues(tracker)
    assert issue.id == "local-1"
    assert issue.identifier == "MEM-1"
    assert issue.labels == ["local", "quick-start"]

    assert {:ok, [%Issue{id: "local-1"}]} = Memory.fetch_issues_by_states(tracker, [" Classifying "])
    assert {:ok, [%Issue{id: "local-1"}]} = Memory.fetch_issue_states_by_ids(tracker, ["local-1"])
  end

  test "can persist local state updates for embedded provider issues" do
    on_exit(fn -> Application.delete_env(:symphony_elixir, :memory_tracker_issue_state_overrides) end)

    tracker = %Config{
      kind: "memory",
      provider: %{
        "persist_state_updates" => true,
        "issues" => [
          %{
            "id" => "local-1",
            "identifier" => "MEM-1",
            "title" => "Local memory issue",
            "state" => "classifying"
          }
        ]
      },
      lifecycle: %{}
    }

    assert {:ok, [%Issue{state: "classifying"}]} = Memory.fetch_issue_states_by_ids(tracker, ["local-1"])
    assert :ok = Memory.update_issue_state(tracker, "local-1", "routed")
    assert {:ok, [%Issue{state: "routed"}]} = Memory.fetch_issue_states_by_ids(tracker, ["local-1"])
  end
end
