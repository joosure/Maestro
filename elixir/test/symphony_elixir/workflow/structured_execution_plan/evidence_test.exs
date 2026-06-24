defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Evidence, as: AgentEvidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  test "validates workflow scope on top of generic Agent evidence refs" do
    ref = workflow_evidence_ref()

    assert {:ok, ^ref} = Evidence.validate_ref(ref)

    generic_ref = Map.delete(ref, Fields.issue_id())
    assert {:ok, ^generic_ref} = AgentEvidence.validate_ref(generic_ref)
  end

  test "requires workflow issue scope without adding issue_id to Agent generic evidence" do
    ref = workflow_evidence_ref()
    generic_ref = Map.delete(ref, Fields.issue_id())

    assert {:error, %{code: code, errors: errors}} = Evidence.validate_ref(generic_ref)
    assert code == ValidationErrorCodes.schema_invalid()

    assert Enum.any?(
             errors,
             &(&1.code == ValidationErrorCodes.missing_required_field() and &1.path == [Fields.issue_id()])
           )

    assert {:error, %{errors: agent_errors}} = AgentEvidence.validate_ref(ref)

    assert Enum.any?(
             agent_errors,
             &(&1.code == ValidationErrorCodes.unknown_key() and &1.path == [Fields.issue_id()])
           )
  end

  test "delegates generic evidence validation errors" do
    ref = Map.put(workflow_evidence_ref(), "source", "untrusted")

    assert {:error, %{errors: errors}} = Evidence.validate_ref(ref)
    assert Enum.any?(errors, &(&1.code == ValidationErrorCodes.invalid_enum() and &1.path == ["source"]))
  end

  defp workflow_evidence_ref do
    %{
      "evidence_id" => "evidence-workflow-1",
      "evidence_kind" => "validation_result",
      "source" => "tool_generated",
      "producer" => "repo_diff",
      "run_id" => "run-workflow-1",
      "issue_id" => "ISSUE-1",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => %{"head_sha" => "abc123"}
    }
  end
end
