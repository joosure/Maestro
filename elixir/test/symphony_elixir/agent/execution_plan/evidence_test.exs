defmodule SymphonyElixir.Agent.ExecutionPlan.EvidenceTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Evidence, as: EvidenceErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Evidence

  test "appends immutable generic evidence refs" do
    item = %{"evidence_refs" => []}
    ref = evidence_ref()
    item_with_ref = %{"evidence_refs" => [ref]}

    assert {:ok, %{"evidence_refs" => [^ref]}} = Evidence.append_ref(item, ref)
    assert {:ok, ^item_with_ref} = Evidence.append_ref(item_with_ref, ref)
  end

  test "rejects conflicting duplicate evidence refs" do
    ref = evidence_ref()
    conflicting_ref = put_in(ref, ["payload", "head_sha"], "other")

    assert {:error, %{code: code}} =
             Evidence.append_ref(%{"evidence_refs" => [ref]}, conflicting_ref)

    assert code == EvidenceErrorCodes.evidence_ref_conflict()
  end

  test "generic evidence refs do not require workflow issue identity" do
    ref = evidence_ref()

    assert {:ok, ^ref} = Evidence.validate_ref(ref)
  end

  test "exposes stable generic validation and evidence error code contracts" do
    assert ValidationErrorCodes.schema_invalid() == "schema_invalid"
    assert ValidationErrorCodes.invalid_type() == "invalid_type"
    assert ValidationErrorCodes.missing_required_field() == "missing_required_field"

    assert EvidenceErrorCodes.invalid_evidence_ref() == "invalid_evidence_ref"
    assert EvidenceErrorCodes.invalid_evidence_refs() == "invalid_evidence_refs"
    assert EvidenceErrorCodes.evidence_ref_conflict() == "evidence_ref_conflict"
  end

  defp evidence_ref do
    %{
      "evidence_id" => "evidence-agent-1",
      "evidence_kind" => "validation_result",
      "source" => "tool_generated",
      "producer" => "repo_diff",
      "run_id" => "run-agent-1",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => %{"head_sha" => "abc123"}
    }
  end
end
