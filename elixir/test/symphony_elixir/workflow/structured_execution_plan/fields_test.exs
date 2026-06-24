defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.FieldsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  test "keeps workflow envelope keys separate from Agent generic fields" do
    assert Fields.issue_id() == "issue_id"
    assert Fields.tracker_kind() == "tracker_kind"
    assert Fields.workflow_profile() == "workflow_profile"
    assert Fields.route_key() == "route_key"

    refute Fields.issue_id() in AgentFields.allowed_plan_keys()
    refute Fields.tracker_kind() in AgentFields.allowed_plan_keys()
    refute Fields.workflow_profile() in AgentFields.allowed_plan_keys()
    refute Fields.route_key() in AgentFields.allowed_plan_keys()
  end

  test "builds workflow evidence refs as generic evidence plus workflow scope" do
    assert Fields.required_evidence_ref_keys() ==
             AgentFields.required_evidence_ref_keys() ++ [Fields.run_id(), Fields.issue_id()]

    assert Fields.issue_id() in Fields.allowed_evidence_ref_keys()
    refute Fields.issue_id() in AgentFields.allowed_evidence_ref_keys()
  end
end
