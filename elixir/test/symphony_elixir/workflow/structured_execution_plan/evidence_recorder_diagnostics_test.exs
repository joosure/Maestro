defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorderDiagnosticsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder

  test "recorder emits compact diagnostics when evidence cannot be recorded" do
    log =
      capture_log(fn ->
        EvidenceRecorder.record_typed_tool_result(
          "repo",
          %{"repository" => "openai/symphony"},
          "repo_commit",
          %{"run_id" => "run-missing-plan", "issue_id" => "TES-79"},
          {:success,
           %{
             "data" => %{
               "action" => "committed",
               "headSha" => "abc123",
               "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
             }
           }},
          gates: %{Contract.enabled_gate_key() => true}
        )
      end)

    assert log =~ "structured_plan_evidence_plan_resolution_failed"
    assert log =~ "error_code=plan_not_found"
    assert log =~ "tool_name=repo_commit"
  end
end
