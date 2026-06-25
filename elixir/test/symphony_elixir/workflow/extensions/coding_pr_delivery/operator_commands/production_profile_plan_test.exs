defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfilePlanTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfilePlan

  test "is registered as a Coding PR Delivery operator command" do
    assert ProductionProfilePlan in CodingPrDelivery.operator_commands()
  end

  test "exports a Phase 2 tiered evidence plan as JSON" do
    assert {stdout, "", 0} =
             ProductionProfilePlan.evaluate(["--phase", "phase2", "--plan", "tiered_reference", "--json"])

    payload = Jason.decode!(stdout)

    assert payload["schema"] == "coding_pr_delivery.phase2_evidence_plan.v1"
    assert payload["plan_kind"] == "tiered_reference"
    assert payload["does_not_call_providers"] == true
    assert payload["does_not_enable_production"] == true

    assert Enum.map(payload["provider_plans"], & &1["template"]) == [
             "linear_github_ready",
             "tapd_cnb_shadow",
             "linear_cnb_shadow"
           ]
  end

  test "exports a Phase 4 review plan with custom shadow run ids" do
    assert {stdout, "", 0} =
             ProductionProfilePlan.evaluate([
               "--phase",
               "phase4",
               "--plan",
               "linear_cnb_shadow",
               "--linear-cnb-shadow-run-id",
               "linear-shadow-cli-1",
               "--pretty"
             ])

    payload = Jason.decode!(stdout)

    assert payload["schema"] == "coding_pr_delivery.phase4_review_plan.v1"
    assert payload["phase4_ready"] == false
    assert payload["review_decision_status"] == "blocked"
    assert payload["does_not_approve_production"] == true
    assert [%{"shadow" => shadow}] = payload["provider_review_plans"]
    assert shadow["run_id"] == "linear-shadow-cli-1"
    assert shadow["canonical_authority"] == false
  end

  test "rejects unknown phases without echoing the supplied value" do
    assert {"", stderr, 64} = ProductionProfilePlan.evaluate(["--phase", "secret-phase"])

    assert stderr =~ "Unsupported phase"
    refute stderr =~ "secret-phase"
  end

  test "rejects unknown plans without echoing the supplied value" do
    assert {"", stderr, 64} = ProductionProfilePlan.evaluate(["--plan", "secret-plan"])

    assert stderr =~ "Coding PR Delivery Phase 2 evidence plan is invalid"
    refute stderr =~ "secret-plan"
  end

  test "does not echo unexpected command arguments" do
    assert {"", stderr, 64} = ProductionProfilePlan.evaluate(["secret-extra"])

    assert stderr =~ "Unexpected argument count: 1"
    refute stderr =~ "secret-extra"
  end

  test "does not echo invalid command options" do
    assert {"", stderr, 64} = ProductionProfilePlan.evaluate(["--secret-option", "secret-value"])

    assert stderr =~ "Invalid option count:"
    refute stderr =~ "--secret-option"
    refute stderr =~ "secret-value"
  end

  test "rejects invalid deps without leaking raw deps" do
    assert {"", stderr, 70} = ProductionProfilePlan.evaluate([], deps: %{secret: true})

    assert stderr =~ "reason=deps_invalid"
    assert stderr =~ "value_type=map"
    refute stderr =~ "secret"
  end

  test "rejects argv lists containing non-strings" do
    assert {"", stderr, 64} = ProductionProfilePlan.evaluate(["--plan", :secret_plan])

    assert stderr =~ "Command argv must contain only strings"
    assert stderr =~ "value_type=atom"
    refute stderr =~ "secret_plan"
  end
end
