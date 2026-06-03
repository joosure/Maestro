defmodule SymphonyElixir.WorkflowLifecycleTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  test "phase behavior predicates normalize string and atom inputs" do
    assert WorkflowLifecycle.human_review_phase?(" Human Review ")
    assert WorkflowLifecycle.human_review_phase?(:human_review)
    refute WorkflowLifecycle.human_review_phase?("review")

    assert WorkflowLifecycle.merge_phase?("Merging")
    assert WorkflowLifecycle.merge_phase?(:merging)
    refute WorkflowLifecycle.merge_phase?("merged")

    assert WorkflowLifecycle.dispatch_blocker_phase?("in progress")
    assert WorkflowLifecycle.dispatch_blocker_phase?(:rework)
    refute WorkflowLifecycle.dispatch_blocker_phase?(:human_review)

    assert WorkflowLifecycle.terminal_phase?(:done)
    assert WorkflowLifecycle.terminal_phase?("Canceled")
    refute WorkflowLifecycle.terminal_phase?(:rework)
  end

  test "state phase validation uses lifecycle behavior categories" do
    valid_tracker = %{
      active_states: ["Todo", "Coding", "Rework"],
      terminal_states: ["Done", "Canceled"],
      state_phase_map: %{
        "Todo" => "todo",
        "Coding" => "in_progress",
        "Rework" => "rework",
        "Done" => "done",
        "Canceled" => "canceled"
      }
    }

    invalid_tracker = %{
      valid_tracker
      | active_states: ["Review"],
        state_phase_map: Map.put(valid_tracker.state_phase_map, "Review", "human_review")
    }

    assert :ok = WorkflowLifecycle.validate_state_phase_map(valid_tracker)

    assert {:error, {:invalid_tracker_state_phase_map, {:invalid_active_phase, "Review", "human_review"}}} =
             WorkflowLifecycle.validate_state_phase_map(invalid_tracker)
  end
end
