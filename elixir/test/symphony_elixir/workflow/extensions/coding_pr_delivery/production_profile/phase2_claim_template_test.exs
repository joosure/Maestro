defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Claim
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRunbook
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "builds a reference Phase 2 claim for Linear + GitHub and TAPD + CNB" do
    assert {:ok, claim} =
             Phase2ClaimTemplate.build(:reference,
               profile_instance_id: "coding_pr_delivery.production.phase2.reference",
               include_linear_github_review_read_exception?: true
             )

    assert {:ok, _normalized_claim} = Claim.validate(claim)
    assert {:ok, runbook} = EvidenceRunbook.build(claim)

    assert ["linear-github-ready", "tapd-cnb-shadow"] ==
             Enum.map(claim["provider_matrix"], & &1["id"])

    assert [%{"exception_id" => "typed-tool-exception-linear-github-review-read"}] =
             claim["typed_tool_exceptions"]

    assert ["linear-github-ready", "tapd-cnb-shadow"] ==
             runbook["entries"] |> Enum.map(& &1["entry_id"])
  end

  test "builds a Linear + GitHub ready-to-land template with transition readiness required" do
    assert {:ok, %{"provider_matrix" => [entry]} = claim} =
             Phase2ClaimTemplate.build("linear_github_ready")

    assert {:ok, _normalized_claim} = Claim.validate(claim)

    assert entry["tracker"] == %{"kind" => "linear"}
    assert entry["repo_provider"] == %{"kind" => "github"}
    assert entry["side_effect_mode"] == "ready_to_land_write"
    assert entry["structured_plan_gates"][Gates.transition_readiness_required_gate_key()] == true
    assert entry["deployment_topology"]["mode"] == "singleton"
    assert claim["typed_tool_exceptions"] == []
  end

  test "builds a TAPD + CNB shadow template with diagnostic-only isolation metadata" do
    assert {:ok, %{"provider_matrix" => [entry]} = claim} =
             Phase2ClaimTemplate.build(:tapd_cnb_shadow, shadow_run_id: "shadow-run-cnb-42")

    assert {:ok, runbook} = EvidenceRunbook.build(claim)

    assert entry["tracker"] == %{"kind" => "tapd"}
    assert entry["repo_provider"] == %{"kind" => "cnb"}
    assert entry["side_effect_mode"] == OneShotContract.shadow_mode()
    assert entry["structured_plan_gates"][Gates.transition_readiness_required_gate_key()] == false
    assert entry["shadow"]["prefix"] == OneShotContract.shadow_prefix()
    assert entry["shadow"]["run_id"] == "shadow-run-cnb-42"
    assert entry["shadow"]["canonical_authority"] == false

    assert [%{"shadow_requirements" => shadow_requirements}] = runbook["entries"]
    assert shadow_requirements["allowed_destinations"] == OneShotContract.shadow_allowed_destinations()
  end

  test "rejects unknown templates before building a production claim" do
    assert {:error, %{code: "coding_pr_delivery_phase2_claim_template_invalid", errors: [error]}} =
             Phase2ClaimTemplate.build(:github_only)

    assert error.code == "unknown_template"
    assert "reference" in error.allowed_values
    assert "tapd_cnb_shadow" in error.allowed_values
  end

  test "exposes templates through the production profile facade" do
    assert "reference" in ProductionProfile.phase2_claim_templates()

    assert {:ok, %{"provider_matrix" => [%{"id" => "tapd-cnb-shadow"}]}} =
             ProductionProfile.phase2_claim_template(:tapd_cnb_shadow)
  end
end
