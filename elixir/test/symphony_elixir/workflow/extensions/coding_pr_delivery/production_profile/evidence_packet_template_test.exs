defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacketTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacketTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplate
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  test "builds Phase 2 evidence packet requirements from a reference claim" do
    assert {:ok, claim} = Phase2ClaimTemplate.build(:reference, shadow_run_id: "shadow-run-cnb-42")
    assert {:ok, template} = EvidencePacketTemplate.build(claim)

    assert template["schema"] == "coding_pr_delivery.production_evidence_packet_template.v1"
    assert template["completed_packet_schema"] == "coding_pr_delivery.production_evidence_packet.v1"
    assert template["template_authority"] == "evidence_packet_shape_only"
    assert template["does_not_collect_live_evidence"] == true

    scenario_count =
      template["runbook"]["entries"]
      |> Enum.flat_map(& &1["scenario_checklist"])
      |> length()

    assert length(template["scenario_evidence_requirements"]) == scenario_count
    assert length(template["non_claim_acknowledgement_requirements"]) == 2
  end

  test "marks Linear + GitHub requirements as real integration evidence" do
    assert {:ok, claim} = Phase2ClaimTemplate.build(:linear_github_ready)
    assert {:ok, template} = EvidencePacketTemplate.build(claim)

    requirement =
      Enum.find(template["scenario_evidence_requirements"], fn requirement ->
        requirement["provider_matrix_entry_id"] == "linear-github-ready" and
          requirement["scenario_id"] == "reconciliation_ready_to_land_write"
      end)

    assert requirement["required_status"] == "passed"
    assert requirement["required_evidence_kind"] == "real_integration"
    assert requirement["shadow"] == nil
    assert requirement["no_write_flags"] == nil
  end

  test "carries TAPD + CNB shadow run id and no-write requirements" do
    assert {:ok, claim} = Phase2ClaimTemplate.build(:tapd_cnb_shadow, shadow_run_id: "shadow-run-cnb-42")
    assert {:ok, template} = EvidencePacketTemplate.build(claim)

    requirement =
      Enum.find(template["scenario_evidence_requirements"], fn requirement ->
        requirement["provider_matrix_entry_id"] == "tapd-cnb-shadow" and
          requirement["scenario_id"] == "shadow_isolation"
      end)

    assert requirement["required_evidence_kind"] == "shadow_integration"
    assert requirement["shadow"]["prefix"] == OneShotContract.shadow_prefix()
    assert requirement["shadow"]["run_id"] == "shadow-run-cnb-42"
    assert requirement["shadow"]["authority"] == OneShotContract.shadow_authority()
    assert requirement["shadow"]["canonical_authority"] == false
    assert requirement["shadow"]["allowed_destinations"] == OneShotContract.shadow_allowed_destinations()

    assert requirement["no_write_flags"] == %{
             "production_write_performed" => false,
             "canonical_surface_mutated" => false
           }
  end

  test "requires non-claim acknowledgement fields per provider entry" do
    assert {:ok, claim} = Phase2ClaimTemplate.build(:tapd_cnb_shadow)
    assert {:ok, template} = EvidencePacketTemplate.build(claim)

    assert [
             %{
               "provider_matrix_entry_id" => "tapd-cnb-shadow",
               "fields_to_complete" => ["owner", "acknowledged_at"],
               "non_claims" => non_claims
             }
           ] = template["non_claim_acknowledgement_requirements"]

    assert "multi_node_ownership" in non_claims
  end

  test "rejects invalid production claims before building requirements" do
    assert {:error, %{code: "coding_pr_delivery_production_claim_invalid", errors: [%{code: "invalid_type"}]}} =
             EvidencePacketTemplate.build(:invalid)
  end

  test "exposes evidence packet templates through the production profile facade" do
    assert {:ok, claim} = ProductionProfile.phase2_claim_template(:tapd_cnb_shadow)

    assert {:ok, %{"schema" => "coding_pr_delivery.production_evidence_packet_template.v1"}} =
             ProductionProfile.phase2_evidence_packet_template(claim)
  end
end
