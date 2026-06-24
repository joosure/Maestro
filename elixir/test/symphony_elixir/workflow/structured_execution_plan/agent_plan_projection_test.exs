defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjectionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjection
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: WorkflowContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields, as: WorkflowFields

  test "projects workflow records to generic Agent plans and restores workflow fields" do
    workflow_plan = workflow_plan()

    agent_plan = AgentPlanProjection.to_agent_plan(workflow_plan)

    assert agent_plan[AgentFields.schema()] == AgentContract.schema_id()
    refute Map.has_key?(agent_plan, WorkflowFields.issue_id())
    refute Map.has_key?(agent_plan, WorkflowFields.tracker_kind())
    refute Map.has_key?(agent_plan, WorkflowFields.workflow_profile())
    refute Map.has_key?(agent_plan, WorkflowFields.route_key())

    assert get_in(agent_plan, [AgentFields.context(), AgentFields.context_kind()]) ==
             WorkflowContract.workflow_context_kind()

    workflow_ref = get_in(agent_plan, [AgentFields.context(), AgentFields.workflow_ref()])

    assert workflow_ref[AgentFields.profile_kind()] == get_in(workflow_plan, [WorkflowFields.workflow_profile(), WorkflowFields.profile_kind()])
    assert workflow_ref[AgentFields.profile_version()] == get_in(workflow_plan, [WorkflowFields.workflow_profile(), WorkflowFields.profile_version()])
    assert workflow_ref[AgentFields.route_key()] == workflow_plan[WorkflowFields.route_key()]
    assert workflow_ref[AgentFields.issue_id()] == workflow_plan[WorkflowFields.issue_id()]
    assert workflow_ref[AgentFields.tracker_kind()] == workflow_plan[WorkflowFields.tracker_kind()]

    assert [agent_item] = agent_plan[AgentFields.items()]
    assert agent_item[AgentFields.kind()] == AgentContract.validation_item_kind()
    assert agent_item[AgentFields.criticality()] == AgentContract.policy_required_criticality()
    assert agent_item[AgentFields.owned_by()] == AgentContract.policy_owner()
    assert agent_item[AgentFields.source()] == AgentContract.policy_skeleton_source()

    assert [agent_ref] = agent_item[AgentFields.evidence_refs()]
    refute Map.has_key?(agent_ref, WorkflowFields.issue_id())

    envelope = AgentPlanProjection.envelope(workflow_plan)

    assert AgentPlanProjection.from_agent_plan(agent_plan, envelope) == workflow_plan
  end

  defp workflow_plan do
    %{
      WorkflowFields.schema() => WorkflowContract.schema_id(),
      WorkflowFields.plan_id() => "plan-projection-1",
      WorkflowFields.run_id() => "run-projection-1",
      WorkflowFields.issue_id() => "ISS-1",
      WorkflowFields.issue_identifier() => "ISS-1",
      WorkflowFields.tracker_kind() => "linear",
      WorkflowFields.workflow_profile() => %{
        WorkflowFields.profile_kind() => "coding_pr_delivery",
        WorkflowFields.profile_version() => 1
      },
      WorkflowFields.route_key() => "developing",
      WorkflowFields.status() => WorkflowContract.active_plan_status(),
      WorkflowFields.items() => [workflow_item()],
      WorkflowFields.created_at() => "2026-06-04T00:00:00Z",
      WorkflowFields.updated_at() => "2026-06-04T00:00:00Z",
      WorkflowFields.revision() => 1
    }
  end

  defp workflow_item do
    %{
      AgentFields.item_id() => "handoff.check",
      AgentFields.parent_item_id() => nil,
      AgentFields.title() => "Validate review handoff evidence",
      AgentFields.kind() => WorkflowContract.handoff_record_item_kind(),
      AgentFields.status() => "pending",
      AgentFields.required() => true,
      AgentFields.criticality() => WorkflowContract.handoff_blocking_criticality(),
      AgentFields.owned_by() => WorkflowContract.profile_owner(),
      AgentFields.source() => WorkflowContract.profile_source(),
      AgentFields.depends_on() => [],
      AgentFields.evidence_requirements() => [],
      AgentFields.evidence_refs() => [workflow_evidence_ref()],
      AgentFields.created_at() => "2026-06-04T00:00:00Z",
      AgentFields.updated_at() => "2026-06-04T00:00:00Z",
      AgentFields.revision() => 1
    }
  end

  defp workflow_evidence_ref do
    %{
      AgentFields.evidence_id() => "evidence-1",
      AgentFields.evidence_kind() => "repo_diff",
      AgentFields.source() => "tool_generated",
      AgentFields.producer() => "repo_diff",
      AgentFields.run_id() => "run-projection-1",
      WorkflowFields.issue_id() => "ISS-1",
      AgentFields.observed_at() => "2026-06-04T00:00:01Z",
      AgentFields.payload() => %{}
    }
  end
end
