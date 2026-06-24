defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.StoreBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Store, as: AgentStoreErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.AgentOwnedItemPolicy
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes

  test "store error-code facade reuses generic store codes and owns workflow-only codes" do
    assert ErrorCodes.plan_not_found() == AgentStoreErrorCodes.plan_not_found()
    assert ErrorCodes.plan_conflict() == AgentStoreErrorCodes.plan_conflict()
    assert ErrorCodes.revision_conflict() == AgentStoreErrorCodes.revision_conflict()
    assert is_binary(ErrorCodes.cross_run_evidence_not_allowed())
    assert is_binary(ErrorCodes.cross_issue_evidence_not_allowed())
    assert is_binary(ErrorCodes.provider_session_event_conflict())
  end

  test "agent-owned item policy consumes workflow item source before generic projection" do
    item = workflow_agent_item()

    assert :ok = AgentOwnedItemPolicy.ensure_upsertable_items([item])

    generic_projected_item = Map.put(item, AgentFields.source(), AgentContract.agent_draft_source())

    assert {:error, %{code: code}} =
             AgentOwnedItemPolicy.ensure_upsertable_items([generic_projected_item])

    assert code == ErrorCodes.item_update_not_allowed()
  end

  defp workflow_agent_item do
    %{
      AgentFields.item_id() => "agent.follow_up",
      AgentFields.owned_by() => Contract.agent_owner(),
      AgentFields.source() => Contract.agent_source(),
      AgentFields.required() => false,
      AgentFields.criticality() => Contract.informational_criticality(),
      AgentFields.evidence_requirements() => [],
      AgentFields.evidence_refs() => []
    }
  end
end
