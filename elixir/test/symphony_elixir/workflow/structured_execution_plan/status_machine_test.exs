defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachineTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.StatusMachine, as: StatusMachineErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine

  test "workflow transition extensions are owned by the workflow contract" do
    assert Contract.workflow_plan_statuses() == ["handoff_ready"]
    assert Contract.agent_plan_status_by_workflow_status() == %{"handoff_ready" => "active"}
    assert Contract.agent_plan_status_for_workflow_status("handoff_ready") == "active"
    assert Contract.agent_plan_status_for_workflow_status("closed") == "closed"
    assert Contract.workflow_plan_status_transitions()["active"] == ["handoff_ready"]
    assert Contract.plan_status_transitions()["active"] == ["blocked", "closed", "superseded", "handoff_ready"]
    assert Contract.plan_status_transitions()["handoff_ready"] == ["active", "closed"]
  end

  test "allows listed plan and item transitions" do
    assert StatusMachine.allowed_plan_transition?("active", "closed")
    assert StatusMachine.allowed_plan_transition?("active", "handoff_ready")
    assert StatusMachine.allowed_plan_transition?("handoff_ready", "active")
    assert StatusMachine.allowed_item_transition?("pending", "in_progress")
  end

  test "forbidden plan status transitions are rejected" do
    assert {:error, %{code: code}} =
             StatusMachine.validate_plan_transition("closed", "active")

    assert code == StatusMachineErrorCodes.plan_status_transition_forbidden()
  end

  test "forbidden item status transitions are rejected" do
    assert {:error, %{code: code}} =
             StatusMachine.validate_item_transition("pending", "failed")

    assert code == StatusMachineErrorCodes.item_status_transition_forbidden()
  end

  test "unknown statuses are rejected before transition validation" do
    assert {:error, %{code: code, status_role: "to_status", status: "unknown_status"}} =
             StatusMachine.validate_plan_transition("active", "unknown_status")

    assert code == ValidationErrorCodes.invalid_enum()
  end
end
