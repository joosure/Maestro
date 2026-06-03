defmodule SymphonyElixir.Workflow.StateTransitionReadiness.FacadeTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StateTransitionReadiness
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoff

  defmodule MatchingPolicyA do
    def policy_id, do: "matching.a.v1"
    def governed_target?(_workflow, "target"), do: true
    def governed_target?(_workflow, _target), do: false
    def validate(_workflow, _issue, _opts), do: :ok
  end

  defmodule MatchingPolicyB do
    def policy_id, do: "matching.b.v1"
    def governed_target?(_workflow, "target"), do: true
    def governed_target?(_workflow, _target), do: false
    def validate(_workflow, _issue, _opts), do: :ok
  end

  test "resolve_policy selects the matching registered policy" do
    workflow = %{
      profile_kind: "coding_pr_delivery",
      raw_state_by_route_key: %{"review" => "In Review"},
      state_phase_map: %{"In Review" => "human_review"}
    }

    assert {:ok, ReviewHandoff} = StateTransitionReadiness.resolve_policy(workflow, "In Review")
    assert StateTransitionReadiness.governed_target?(workflow, "In Review")
  end

  test "resolve_policy distinguishes not governed targets from passed readiness" do
    workflow = %{
      profile_kind: "coding_pr_delivery",
      raw_state_by_route_key: %{"developing" => "In Progress"},
      state_phase_map: %{"In Progress" => "in_progress"}
    }

    assert {:ok, :not_governed} = StateTransitionReadiness.resolve_policy(workflow, "In Progress")
    refute StateTransitionReadiness.governed_target?(workflow, "In Progress")

    assert :ok =
             StateTransitionReadiness.validate(workflow, %{}, target_state_name: "In Progress")
  end

  test "resolve_policy fails closed when multiple policies match" do
    opts = [readiness_policies: [MatchingPolicyA, MatchingPolicyB]]

    assert {:error, {:ambiguous_readiness_policy, ["matching.a.v1", "matching.b.v1"]}} =
             StateTransitionReadiness.resolve_policy(%{}, "target", opts)

    assert StateTransitionReadiness.governed_target?(%{}, "target", opts)

    assert {:error, {:ambiguous_readiness_policy, ["matching.a.v1", "matching.b.v1"]}} =
             StateTransitionReadiness.validate(
               %{},
               %{},
               Keyword.put(opts, :target_state_name, "target")
             )
  end
end
