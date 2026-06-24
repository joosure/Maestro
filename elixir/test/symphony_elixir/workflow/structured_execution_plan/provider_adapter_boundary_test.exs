defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapterBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Contract, as: AgentToolContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Guard
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Result

  @gate Contract.provider_adapters_enabled_gate_key()

  test "options owns canonical provider-adapter gate parsing" do
    assert Options.enabled?(gates: %{@gate => true})
    assert Options.enabled?(structured_execution_plan: %{@gate => true})

    refute Options.enabled?(structured_execution_plan: %{provider_adapters_enabled: true})
  end

  test "result owns provider-adapter gate-disabled contract" do
    assert %{
             "success" => true,
             "status" => "skipped",
             "reason" => reason,
             "gate" => @gate,
             "plan_changed" => false
           } = Result.skipped()

    assert reason == ErrorCodes.provider_adapters_gate_disabled()

    assert {:failure, %{"error" => %{"code" => ^reason, "details" => %{"gate" => @gate}}}} =
             Result.gate_disabled_typed_failure()
  end

  test "guard summarizes missing required evidence using field contracts" do
    evidence_kinds_key = AgentToolContract.evidence_kinds_key()

    assert {:error,
            %{
              code: code,
              status: "blocked",
              missing_items: [
                %{
                  "item_id" => "repo.push",
                  "status" => "pending",
                  ^evidence_kinds_key => ["repo_push"]
                }
              ]
            }} = Guard.task_completed(plan())

    assert code == ErrorCodes.structured_plan_missing_required_evidence()
  end

  defp plan do
    %{
      AgentFields.items() => [
        %{
          AgentFields.item_id() => "repo.push",
          AgentFields.status() => "pending",
          AgentFields.required() => true,
          AgentFields.criticality() => Contract.handoff_blocking_criticality(),
          AgentFields.evidence_requirements() => [
            %{AgentFields.evidence_kind() => "repo_push"}
          ],
          AgentFields.evidence_refs() => []
        }
      ]
    }
  end
end
