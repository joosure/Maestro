defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBindingTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values, as: ReadinessValues
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.CheckStatus
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.CheckStatus.Contract, as: CheckStatusContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields, as: WorkflowFields

  @run_id "run-1"
  @issue_id "TES-1"

  test "raw input owns runtime metadata key" do
    assert RawInput.runtime_metadata(%{RawInput.runtime_metadata_key() => %{"run_id" => "run-1"}}) == %{"run_id" => "run-1"}
  end

  test "check status owns provider checks payload fields" do
    assert CheckStatus.status(%{CheckStatusContract.runs_key() => [%{CheckStatusContract.bucket_key() => ReadinessValues.passed_status()}]}) ==
             ReadinessValues.passed_status()

    assert CheckStatus.status(%{CheckStatusContract.summary_key() => %{ReadinessValues.failed_status() => 1}}) ==
             ReadinessValues.failed_status()
  end

  test "tool map owns typed tool to provider-neutral evidence kind mapping" do
    refute EvidenceBinding.evidence_kind("linear_move_issue")
    refute EvidenceBinding.evidence_kind("tapd_move_issue")

    assert EvidenceBinding.evidence_kind("jira_move_issue", tool_context: tool_context("jira_move_issue", TrackerCapabilities.move_issue())) ==
             ToolMap.tracker_move_issue_evidence_kind()

    assert EvidenceBinding.evidence_kind("repo_commit") == ToolMap.repo_commit_evidence_kind()
    assert EvidenceBinding.evidence_kind("unknown_tool") == nil
  end

  test "bound evidence refs use field and trust-class contracts" do
    assert {:ok, [ref]} =
             EvidenceBinding.bind_typed_tool_result(
               "repo",
               %{"repository" => "openai/symphony"},
               "repo_commit",
               %{run_id: "run-1", issue_id: "TES-1"},
               {:success,
                %{
                  "data" => %{
                    "action" => "committed",
                    "headSha" => "abc123",
                    "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
                  }
                }},
               observed_at: "2026-05-20T00:00:01Z"
             )

    assert Map.fetch!(ref, AgentFields.source()) == AgentContract.tool_generated_trust_class()
    assert Map.fetch!(ref, AgentFields.evidence_kind()) == ToolMap.repo_commit_evidence_kind()
    assert Map.fetch!(ref, WorkflowFields.run_id()) == "run-1"
    assert Map.fetch!(ref, WorkflowFields.issue_id()) == "TES-1"
  end

  test "tracker evidence binding is capability-driven instead of tracker-name-driven" do
    assert {:ok, [ref]} =
             EvidenceBinding.bind_typed_tool_result(
               "tracker",
               %{kind: "jira"},
               "jira_move_issue",
               %{"run_id" => @run_id, "issue_id" => @issue_id, "state_name" => "In Review"},
               {:success, %{"data" => %{"issue" => %{"id" => @issue_id, "state" => %{"id" => "state-1", "name" => "In Review"}}}}},
               tool_context: tool_context("jira_move_issue", TrackerCapabilities.move_issue()),
               observed_at: "2026-05-20T00:00:01Z"
             )

    assert Map.fetch!(ref, AgentFields.evidence_kind()) == ToolMap.tracker_move_issue_evidence_kind()
    assert Map.fetch!(ref, AgentFields.producer()) == "jira_move_issue"
    assert Map.fetch!(ref, AgentFields.payload())["tracker_kind"] == "tracker"
  end

  test "scope errors use evidence-binding error-code contract" do
    assert {:error, %{code: missing_run_id}} =
             EvidenceBinding.bind_typed_tool_result(
               "repo",
               %{},
               "repo_commit",
               %{issue_id: "TES-1"},
               {:success, %{"data" => %{}}},
               []
             )

    assert missing_run_id == ErrorCodes.missing_run_id()

    assert {:error, %{code: missing_issue_id}} =
             EvidenceBinding.bind_typed_tool_result(
               "repo",
               %{},
               "repo_commit",
               %{run_id: "run-1"},
               {:success, %{"data" => %{}}},
               []
             )

    assert missing_issue_id == ErrorCodes.missing_issue_id()
  end

  defp tool_context(tool, capability) do
    %{
      tool_metadata: %{
        tool => %{
          Metadata.Contract.capability() => capability
        }
      }
    }
  end
end
