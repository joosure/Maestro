defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRequestTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRequest
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  test "summarizes provider access and target requirements for the tiered plan" do
    assert {:ok, request} = EvidenceRequest.build(:tiered_reference)

    assert request["schema"] == "coding_pr_delivery.production_evidence_request.v1"
    assert request["status"] == "blocked_pending_external_evidence"
    assert request["provider_request_count"] == 3
    assert request["does_not_call_providers"] == true
    assert request["does_not_read_evidence_files"] == true
    assert request["does_not_enable_production"] == true
    assert request["raw_input_included"] == false
    assert request["normalized_plan_included"] == false

    summary = request["external_input_summary"]
    assert "LINEAR_API_KEY" in summary["required_env"]
    assert "TAPD_API_USER" in summary["required_env"]
    assert "CNB_TOKEN" in summary["required_env"]
    assert "gh auth status" in summary["required_auth"]
    assert "repo_slug" in summary["required_targets"]
    assert "change_proposal_number" in summary["required_targets"]
    assert "provider_read_only_smoke" in summary["required_runtime"]
  end

  test "keeps Linear + CNB shadow evidence requests diagnostic-only" do
    assert {:ok, request} =
             EvidenceRequest.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: "linear-shadow-evidence-request")

    assert [provider_request] = request["provider_requests"]

    assert provider_request["template"] == "linear_cnb_shadow"
    assert provider_request["tracker_kinds"] == ["linear"]
    assert provider_request["repo_provider_kinds"] == ["cnb"]
    assert provider_request["side_effect_modes"] == [OneShotContract.shadow_mode()]
    assert "collect_shadow_no_write_evidence" in provider_request["owner_actions"]
    assert provider_request["does_not_authorize_production_writes"] == true

    assert ["LINEAR_API_KEY", "LINEAR_PROJECT_SLUG", "CNB_TOKEN"] =
             provider_request["required_access"]["required_env"]

    assert Enum.any?(provider_request["read_only_preflight_commands"], &(&1["id"] == "linear-tracker-read-only-smoke"))
    assert Enum.any?(provider_request["read_only_preflight_commands"], &(&1["id"] == "cnb-repo-provider-read-only-smoke"))

    assert [%{"shadow" => shadow} | _rest] = provider_request["evidence_requirements"]
    assert shadow["prefix"] == OneShotContract.shadow_prefix()
    assert shadow["run_id"] == "linear-shadow-evidence-request"
    assert shadow["authority"] == OneShotContract.shadow_authority()
    assert shadow["canonical_authority"] == false
    assert OneShotContract.shadow_allowed_destinations() == shadow["allowed_destinations"]

    assert [%{"non_claims" => non_claims}] = provider_request["non_claim_acknowledgements"]
    assert "multi_node_ownership" in non_claims
    assert "automatic_durable_replay" in non_claims
  end

  test "exposes evidence requests through the production profile facade" do
    assert {:ok, %{"schema" => "coding_pr_delivery.production_evidence_request.v1"}} =
             ProductionProfile.production_evidence_request(:linear_github_ready)
  end

  test "rejects invalid options without provider calls" do
    assert {:error, %{code: "coding_pr_delivery_evidence_request_invalid", errors: [error]}} =
             EvidenceRequest.build(:tiered_reference, :not_keyword)

    assert error.code == "invalid_options"
  end
end
