defmodule SymphonyElixir.Agent.ExecutionPlan.StatusMachineTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.StatusMachine, as: StatusMachineErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.StatusMachine

  test "allows provider-neutral plan and item transitions" do
    assert StatusMachine.allowed_plan_transition?("active", "closed")
    assert StatusMachine.allowed_item_transition?("pending", "in_progress")
  end

  test "rejects workflow-only statuses before transition validation" do
    refute StatusMachine.allowed_plan_transition?("active", "handoff_ready")

    assert {:error, %{code: code}} =
             StatusMachine.validate_plan_transition("active", "handoff_ready")

    assert code == ValidationErrorCodes.invalid_enum()
  end

  test "rejects forbidden transitions after enum validation" do
    assert {:error, %{code: code}} =
             StatusMachine.validate_plan_transition("closed", "active")

    assert code == StatusMachineErrorCodes.plan_status_transition_forbidden()
  end
end
