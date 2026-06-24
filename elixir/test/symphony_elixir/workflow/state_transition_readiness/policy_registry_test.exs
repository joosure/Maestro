defmodule SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder
  alias SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry

  test "derives readiness policies and evidence recorders from registered workflow extensions" do
    opts = [entries: [CodingPrDelivery]]

    assert PolicyRegistry.policies(opts) == [ReviewHandoff]
    assert PolicyRegistry.evidence_recorders(opts) == [EvidenceRecorder]
    assert :ok = PolicyRegistry.validate(opts)
  end

  test "registered policies expose the readiness policy contract" do
    [_policy | _policies] = policies = PolicyRegistry.policies()

    for policy <- policies do
      Code.ensure_loaded!(policy)
      assert function_exported?(policy, :policy_id, 0)
      assert function_exported?(policy, :schema, 0)
      assert function_exported?(policy, :governed_target?, 2)
      assert function_exported?(policy, :validate, 3)
      assert is_binary(policy.policy_id())
      assert is_binary(policy.schema())
    end
  end

  test "registered evidence recorders expose the typed-tool recording contract" do
    [_recorder | _recorders] = recorders = PolicyRegistry.evidence_recorders()

    for recorder <- recorders do
      Code.ensure_loaded!(recorder)
      assert function_exported?(recorder, :record_typed_tool_result, 6)
    end
  end
end
