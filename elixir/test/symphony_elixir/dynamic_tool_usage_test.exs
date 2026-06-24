defmodule SymphonyElixir.Agent.DynamicToolUsageTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Usage
  alias SymphonyElixir.Agent.DynamicTool.Usage.Classification

  test "classify returns a stable classification struct from normalized context" do
    context =
      Context.normalize(%{
        "tool_specs" => [
          %{
            "name" => "typed_probe",
            "description" => "Typed probe.",
            "inputSchema" => %{"type" => "object"}
          }
        ],
        "tool_metadata" => %{
          "typed_probe" => %{
            "capability" => "test.probe",
            "sideEffect" => "read_only",
            "sourceKind" => "test",
            "schemaVersion" => "1"
          }
        },
        "tool_plan" => %{"exposure" => "restricted"}
      })

    assert %Classification{
             usage_kind: "typed",
             tool_name: "typed_probe",
             capability: "test.probe",
             side_effect: "read_only",
             source_kind: "test",
             schema_version: "1",
             operator_only?: false,
             exposure: "restricted"
           } = Usage.classify(context, "typed_probe")

    assert Usage.audit_fields(context, "typed_probe") == %{
             dynamic_tool_usage_kind: "typed",
             dynamic_tool_capability: "test.probe",
             dynamic_tool_side_effect: "read_only",
             dynamic_tool_source_kind: "test",
             dynamic_tool_schema_version: "1",
             dynamic_tool_operator_only: false,
             dynamic_tool_exposure: "restricted"
           }
  end

  test "failure_reason reads only canonical bridge responses" do
    canonical = %{"success" => false, "payload" => %{"error" => %{"code" => "canonical_failure"}}}

    assert Usage.failure_reason(canonical) == "canonical_failure"
    assert Usage.failure_reason(%{payload: %{error: %{code: "legacy_failure"}}}) == nil
  end

  test "provider capability unavailable details use stable detail structs before projection" do
    payload = %{
      "payload" => %{
        "actions" => [
          %{
            "capability" => "repo.submit_review",
            "description" => "Submit a review.",
            "reason" => "provider_capability_not_available"
          }
        ]
      }
    }

    assert Usage.provider_capability_unavailable_count(payload) == 1

    assert Usage.provider_capability_unavailable_details(payload) == [
             %{
               "capability" => "repo.submit_review",
               "description" => "Submit a review.",
               "reason" => "provider_capability_not_available"
             }
           ]
  end
end
