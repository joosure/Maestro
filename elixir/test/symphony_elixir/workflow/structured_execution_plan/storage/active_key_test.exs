defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.ActiveKeyTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.ActiveKey

  test "builds the canonical active route/profile lookup key from workflow fields" do
    envelope = envelope()

    assert ActiveKey.active?(envelope)

    assert ActiveKey.from_envelope!(envelope) == {
             "run/1",
             "coding pr delivery",
             1,
             "developing/review"
           }

    assert ActiveKey.encode(ActiveKey.from_envelope!(envelope)) ==
             "run%2F1/coding+pr+delivery/1/developing%2Freview"
  end

  test "does not treat non-active workflow plans as active" do
    refute ActiveKey.active?(Map.put(envelope(), Fields.status(), "closed"))
    refute ActiveKey.active?(%{})
  end

  defp envelope do
    %{
      Fields.plan_id() => "plan-1",
      Fields.run_id() => "run/1",
      Fields.workflow_profile() => %{
        Fields.profile_kind() => "coding pr delivery",
        Fields.profile_version() => 1
      },
      Fields.route_key() => "developing/review",
      Fields.status() => Contract.active_plan_status()
    }
  end
end
