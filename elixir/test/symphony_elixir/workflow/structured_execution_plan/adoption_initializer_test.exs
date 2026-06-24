defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Request
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.RequestBuilder
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "skips when structured execution plan adoption is disabled", %{store: store} do
    assert {:ok, %{status: :skipped, reason: :gate_disabled, profile: nil}} =
             AdoptionInitializer.create_for_issue(settings("requirement_analysis", false), issue(), context_opts(store))
  end

  test "skips when resolved profile has no adoption module", %{store: store} do
    assert {:ok, %{status: :skipped, reason: :profile_not_adopted, profile: %{"kind" => "coding_pr_delivery", "version" => 1}}} =
             AdoptionInitializer.create_for_issue(settings("coding_pr_delivery", true), issue(), context_opts(store))
  end

  test "creates profile-owned plan and active store entry when enabled", %{store: store} do
    assert {:ok, %{status: :created, plan: plan, snapshot: snapshot}} =
             AdoptionInitializer.create_for_issue(settings("requirement_analysis", true), issue(), context_opts(store))

    assert plan["schema"] == "workflow.execution_plan.v1"
    assert plan["plan_id"] == "plan-adoption-test"
    assert plan["run_id"] == "run-adoption-test"
    assert plan["issue_id"] == "ISSUE-1"
    assert plan["issue_identifier"] == "REQ-1"
    assert plan["tracker_kind"] == "tracker-test"
    assert plan["workflow_profile"] == %{"kind" => "requirement_analysis", "version" => 1}
    assert plan["route_key"] == "analyzing"
    assert snapshot["item_count"] == length(plan["items"])

    assert {:ok, ^plan} =
             Store.active_plan(
               "run-adoption-test",
               %{"kind" => "requirement_analysis", "version" => 1},
               "analyzing",
               server: store
             )
  end

  test "creates from normalized request without raw settings after boundary build", %{store: store} do
    request = RequestBuilder.build(settings("requirement_analysis", true), issue(), context_opts(store))

    assert %Request{enabled?: true, registry_profile_config: %{"kind" => "requirement_analysis"}} = request

    assert {:ok, %{status: :created, plan: %{"plan_id" => "plan-adoption-test"}}} =
             AdoptionInitializer.create(request)
  end

  test "returns store conflict for duplicate active adoption plan", %{store: store} do
    assert {:ok, %{status: :created}} =
             AdoptionInitializer.create_for_issue(settings("requirement_analysis", true), issue(), context_opts(store, plan_id: "plan-a"))

    assert {:error, %{code: "plan_conflict", active_plan_id: "plan-a"}} =
             AdoptionInitializer.create_for_issue(settings("requirement_analysis", true), issue(), context_opts(store, plan_id: "plan-b"))
  end

  test "fails closed when required run or issue context is missing", %{store: store} do
    assert {:error, %{code: "structured_plan_adoption_missing_context", fields: fields}} =
             AdoptionInitializer.create_for_issue(
               settings("requirement_analysis", true),
               %{},
               server: store,
               tracker_kind: "tracker-test"
             )

    assert "run_id" in fields
    assert "issue_id" in fields
  end

  test "strips adoption gate from profile registry config while preserving profile options" do
    request =
      "requirement_analysis"
      |> settings(true)
      |> put_in(["workflow", "profile", "options", "question_policy"], "blocking_only")
      |> RequestBuilder.build(issue(), [])

    assert request.registry_profile_config["options"]["question_policy"] == "blocking_only"
    refute Map.has_key?(request.registry_profile_config["options"], "structured_execution_plan")
  end

  test "initializer does not reference concrete profile modules" do
    source =
      "lib/symphony_elixir/workflow/structured_execution_plan/adoption_initializer.ex"
      |> Path.expand(File.cwd!())
      |> File.read!()

    refute source =~ "RequirementAnalysis"
    refute source =~ "CodingPrDelivery"
    refute source =~ "RequirementRefinement"
    refute source =~ "ReviewRouting"
    refute source =~ "Triage"
  end

  defp settings(kind, enabled?) do
    %{
      "workflow" => %{
        "profile" => %{
          "kind" => kind,
          "version" => 1,
          "options" => %{
            "structured_execution_plan" => %{"enabled" => enabled?}
          }
        }
      }
    }
  end

  defp issue do
    %{id: "ISSUE-1", identifier: "REQ-1"}
  end

  defp context_opts(store, overrides \\ []) do
    [
      server: store,
      plan_id: "plan-adoption-test",
      run_id: "run-adoption-test",
      tracker_kind: "tracker-test",
      created_at: "2026-06-05T00:00:00Z"
    ]
    |> Keyword.merge(overrides)
  end
end
