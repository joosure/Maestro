defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachineTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine

  test "allows listed plan and item transitions" do
    assert StatusMachine.allowed_plan_transition?("active", "closed")
    assert StatusMachine.allowed_item_transition?("pending", "in_progress")
  end

  test "forbidden plan status transitions are rejected" do
    assert {:error, %{code: "plan_status_transition_forbidden"}} =
             StatusMachine.validate_plan_transition("closed", "active")
  end

  test "forbidden item status transitions are rejected" do
    assert {:error, %{code: "item_status_transition_forbidden"}} =
             StatusMachine.validate_item_transition("pending", "failed")
  end
end
