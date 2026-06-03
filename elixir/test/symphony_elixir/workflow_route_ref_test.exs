defmodule SymphonyElixir.WorkflowRouteRefTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.RouteRef

  test "creates a validated profile-scoped route identity" do
    assert {:ok,
            %RouteRef{
              profile_kind: "coding_pr_delivery",
              profile_version: 1,
              route_key: :review
            } = route_ref} = RouteRef.new(%{kind: "coding_pr_delivery", version: 1}, " review ")

    assert RouteRef.event_fields(route_ref) == %{
             workflow_profile: "coding_pr_delivery",
             workflow_profile_version: 1,
             workflow_route_key: "review"
           }

    assert RouteRef.storage_key("run-1", route_ref) == {"run-1", "coding_pr_delivery", 1, "review"}
  end

  test "normalizes string-keyed profile contexts" do
    route_ref = RouteRef.new!(%{"kind" => "requirement_analysis", "version" => 1}, " review ")

    assert RouteRef.string_fields(route_ref) == %{
             "workflow_profile" => "requirement_analysis",
             "workflow_profile_version" => 1,
             "workflow_route_key" => "review"
           }
  end

  test "rejects route keys outside the workflow profile scope" do
    assert {:error, {:invalid_workflow_route_key, "requirement_analysis", 1, "developing"}} =
             RouteRef.new(%{"kind" => "requirement_analysis", "version" => 1}, "developing")
  end

  test "target-route event fields are generated from a route ref" do
    target_route_ref = RouteRef.new!(%{kind: "coding_pr_delivery", version: 1}, :merging)

    assert RouteRef.transition_target_event_fields(target_route_ref) == %{
             workflow_transition_target_route_key: "merging"
           }
  end
end
