defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorderBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder.PlanResolver
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @plan_id "plan-recorder-boundary-1"
  @run_id "run-recorder-boundary-1"
  @profile %{"kind" => "coding_pr_delivery", "version" => 1}
  @route_key "developing"
  @created_at "2026-05-20T00:00:00Z"

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "options owns recorder gate and store option parsing", %{store: store} do
    opts = [
      gates: %{Contract.enabled_gate_key() => true},
      structured_execution_plan: %{"plan_id" => @plan_id, "server" => store},
      updated_at: "2026-05-20T00:00:01Z"
    ]

    assert Options.enabled?(opts)
    assert Options.plan_id(opts) == @plan_id
    assert Options.store_opts(opts) == [updated_at: "2026-05-20T00:00:01Z", server: store]
  end

  test "plan resolver uses direct plan id when provided" do
    assert PlanResolver.resolve_plan_id(structured_execution_plan: %{plan_id: @plan_id}) == {:ok, @plan_id}
  end

  test "plan resolver can resolve active plan using normalized recorder options", %{store: store} do
    assert {:ok, _plan} = Store.create(plan(), server: store)
    runtime_metadata_key = RawInput.runtime_metadata_key()

    opts = [
      structured_execution_plan: %{
        "workflow_profile" => @profile,
        "route_key" => @route_key,
        "server" => store
      },
      tool_context: %{runtime_metadata_key => %{"run_id" => @run_id}}
    ]

    assert PlanResolver.resolve_plan_id(opts) == {:ok, @plan_id}
  end

  defp plan do
    %{
      "schema" => Contract.schema_id(),
      "plan_id" => @plan_id,
      "run_id" => @run_id,
      "issue_id" => "TES-79",
      "tracker_kind" => "linear",
      "workflow_profile" => @profile,
      "route_key" => @route_key,
      "status" => Contract.active_plan_status(),
      "items" => [],
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end
end
