defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileEvidenceRequestTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileEvidenceRequest

  test "is registered as a Coding PR Delivery operator command" do
    assert ProductionProfileEvidenceRequest in CodingPrDelivery.operator_commands()
  end

  test "exports bounded evidence requests for provider owners" do
    assert {stdout, "", 0} =
             ProductionProfileEvidenceRequest.evaluate(["--plan", "tiered_reference", "--json"])

    payload = Jason.decode!(stdout)

    assert payload["schema"] == "coding_pr_delivery.production_evidence_request.v1"
    assert payload["status"] == "blocked_pending_external_evidence"
    assert payload["provider_request_count"] == 3
    assert payload["does_not_call_providers"] == true
    assert payload["does_not_enable_production"] == true
    assert "CNB_TOKEN" in payload["external_input_summary"]["required_env"]
    assert "repo_slug" in payload["external_input_summary"]["required_targets"]
  end

  test "can project from a Phase 2 plan file without reading evidence files" do
    assert {:ok, phase2_plan} =
             SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.phase2_evidence_plan(:linear_cnb_shadow)

    deps = %{
      read_file: fn "phase2.json" -> {:ok, Jason.encode!(phase2_plan)} end,
      production_evidence_request: fn input, opts ->
        SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.production_evidence_request(input, opts)
      end
    }

    assert {stdout, "", 0} =
             ProductionProfileEvidenceRequest.evaluate(["--phase2-plan-file", "phase2.json", "--pretty"], deps: deps)

    payload = Jason.decode!(stdout)

    assert payload["phase2_plan_kind"] == "linear_cnb_shadow"
    assert payload["provider_request_count"] == 1
    assert payload["does_not_read_evidence_files"] == true
    assert [%{"template" => "linear_cnb_shadow"}] = payload["provider_requests"]
  end

  test "does not echo unreadable file paths or raw args" do
    deps = %{
      read_file: fn _path -> {:error, :enoent} end,
      production_evidence_request: fn _input, _opts -> flunk("request should not run") end
    }

    assert {"", stderr, 64} =
             ProductionProfileEvidenceRequest.evaluate(["--phase2-plan-file", "secret-phase2.json"], deps: deps)

    assert stderr =~ "Phase 2 plan file could not be read or parsed."
    refute stderr =~ "secret-phase2"

    assert {"", argv_stderr, 64} =
             ProductionProfileEvidenceRequest.evaluate(["--plan", :secret_plan], deps: valid_deps())

    assert argv_stderr =~ "Command argv must contain only strings"
    assert argv_stderr =~ "value_type=atom"
    refute argv_stderr =~ "secret_plan"
  end

  test "rejects invalid deps without leaking raw deps" do
    assert {"", stderr, 70} = ProductionProfileEvidenceRequest.evaluate([], deps: %{secret: true})

    assert stderr =~ "reason=deps_invalid"
    assert stderr =~ "value_type=map"
    refute stderr =~ "secret"
  end

  defp valid_deps do
    %{
      read_file: fn _path -> {:error, :enoent} end,
      production_evidence_request: fn input, opts ->
        SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.production_evidence_request(input, opts)
      end
    }
  end
end
