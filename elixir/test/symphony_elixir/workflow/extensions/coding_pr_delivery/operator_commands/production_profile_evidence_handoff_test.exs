defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileEvidenceHandoffTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileEvidenceHandoff
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  test "is registered as a Coding PR Delivery operator command" do
    assert ProductionProfileEvidenceHandoff in CodingPrDelivery.operator_commands()
  end

  test "exports a bounded blocked handoff for the default Phase 2 plan" do
    assert {stdout, "", 0} = ProductionProfileEvidenceHandoff.evaluate(["--plan", "linear_cnb_shadow", "--json"])

    payload = Jason.decode!(stdout)

    assert payload["schema"] == "coding_pr_delivery.production_evidence_handoff.v1"
    assert payload["status"] == "blocked_pending_external_evidence"
    assert payload["phase4_ready"] == false
    assert payload["preflight"]["status"] == "missing"
    assert payload["evidence_bundle"]["status"] == "blocked"
    assert payload["does_not_read_evidence_files"] == true
    assert payload["does_not_call_providers"] == true
    assert payload["does_not_enable_production"] == true
  end

  test "merges request, preflight, and evidence packet files without reading referenced evidence" do
    phase2_plan = phase2_plan()
    assert {:ok, evidence_request} = ProductionProfile.production_evidence_request(phase2_plan)
    preflight_report = passed_preflight_report(phase2_plan)
    evidence_packet = completed_evidence_packet(List.first(phase2_plan["provider_plans"]))

    deps = %{
      read_file: fn
        "phase2.json" -> {:ok, Jason.encode!(phase2_plan)}
        "request.json" -> {:ok, Jason.encode!(evidence_request)}
        "preflight.json" -> {:ok, Jason.encode!(preflight_report)}
        "evidence.json" -> {:ok, Jason.encode!(evidence_packet)}
      end,
      production_evidence_handoff: fn input, opts -> ProductionProfile.production_evidence_handoff(input, opts) end
    }

    assert {stdout, "", 0} =
             ProductionProfileEvidenceHandoff.evaluate(
               [
                 "--phase2-plan-file",
                 "phase2.json",
                 "--evidence-request-file",
                 "request.json",
                 "--preflight-report-file",
                 "preflight.json",
                 "--evidence-packet-file",
                 "evidence.json",
                 "--pretty"
               ],
               deps: deps
             )

    payload = Jason.decode!(stdout)

    assert payload["status"] == "ready_for_phase4_review"
    assert payload["preflight"]["status"] == "passed"
    assert payload["evidence_bundle"]["phase4_ready"] == true
    assert payload["provider_handoffs"] |> List.first() |> Map.fetch!("evidence_packet_status") == "valid"
    assert payload["blockers"] == []
  end

  test "does not echo unreadable file paths or raw args" do
    deps = %{
      read_file: fn _path -> {:error, :enoent} end,
      production_evidence_handoff: fn _input, _opts -> flunk("handoff should not run") end
    }

    assert {"", stderr, 64} =
             ProductionProfileEvidenceHandoff.evaluate(["--phase2-plan-file", "secret-phase2.json"], deps: deps)

    assert stderr =~ "Phase 2 plan file could not be read or parsed."
    refute stderr =~ "secret-phase2"

    assert {"", argv_stderr, 64} =
             ProductionProfileEvidenceHandoff.evaluate(["--plan", :secret_plan], deps: valid_deps())

    assert argv_stderr =~ "Command argv must contain only strings"
    assert argv_stderr =~ "value_type=atom"
    refute argv_stderr =~ "secret_plan"
  end

  test "rejects invalid deps without leaking raw deps" do
    assert {"", stderr, 70} = ProductionProfileEvidenceHandoff.evaluate([], deps: %{secret: true})

    assert stderr =~ "reason=deps_invalid"
    assert stderr =~ "value_type=map"
    refute stderr =~ "secret"
  end

  defp phase2_plan do
    assert {:ok, plan} =
             ProductionProfile.phase2_evidence_plan(:linear_cnb_shadow,
               linear_cnb_shadow_run_id: "handoff-command-shadow"
             )

    plan
  end

  defp passed_preflight_report(phase2_plan) do
    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => preflight_results(phase2_plan),
      "explicit_non_claims" => [
        "preflight_report_does_not_collect_live_provider_evidence",
        "preflight_report_does_not_enable_production"
      ]
    }
  end

  defp preflight_results(phase2_plan) do
    phase2_plan
    |> Map.fetch!("provider_plans")
    |> Enum.flat_map(fn provider_plan ->
      provider_plan
      |> get_in(["read_only_preflight", "commands"])
      |> Enum.map(fn command ->
        %{
          "template" => Map.fetch!(provider_plan, "template"),
          "command_id" => Map.fetch!(command, "id"),
          "target" => Map.fetch!(command, "target"),
          "provider_kind" => Map.fetch!(command, "provider_kind"),
          "status" => "passed",
          "ran_at" => "2026-06-26T06:40:00Z",
          "side_effect_mode" => "read_only",
          "write_performed" => false,
          "production_enabled" => false,
          "missing_prerequisites" => [],
          "evidence_files" => ["evidence/preflight/#{Map.fetch!(command, "id")}.md"]
        }
      end)
    end)
  end

  defp completed_evidence_packet(provider_plan) do
    runbook = Map.fetch!(provider_plan, "evidence_runbook")

    %{
      "production_claim" => Map.fetch!(provider_plan, "production_claim"),
      "scenario_evidence" => scenario_evidence(runbook),
      "non_claim_acknowledgements" => non_claim_acknowledgements(runbook)
    }
  end

  defp scenario_evidence(runbook) do
    Enum.flat_map(runbook["entries"], fn entry ->
      Enum.map(entry["scenario_checklist"], fn scenario ->
        %{
          "provider_matrix_entry_id" => entry["entry_id"],
          "scenario_id" => scenario["id"],
          "status" => "passed",
          "evidence_kind" => "shadow_integration",
          "collector" => "provider-integration-owner",
          "collected_at" => "2026-06-26T06:40:00Z",
          "evidence_files" => ["evidence/live/#{entry["entry_id"]}/#{scenario["id"]}.md"],
          "production_write_performed" => false,
          "canonical_surface_mutated" => false,
          "shadow" => %{
            "prefix" => OneShotContract.shadow_prefix(),
            "run_id" => get_in(entry, ["shadow_requirements", "run_id"]) || "handoff-command-shadow",
            "authority" => OneShotContract.shadow_authority(),
            "canonical_authority" => false,
            "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
          }
        }
      end)
    end)
  end

  defp non_claim_acknowledgements(runbook) do
    Enum.map(runbook["entries"], fn entry ->
      %{
        "provider_matrix_entry_id" => entry["entry_id"],
        "non_claims" => entry["non_claims"],
        "owner" => "provider-integration-owner",
        "acknowledged_at" => "2026-06-26T06:40:00Z"
      }
    end)
  end

  defp valid_deps do
    %{
      read_file: fn _path -> {:error, :enoent} end,
      production_evidence_handoff: fn input, opts -> ProductionProfile.production_evidence_handoff(input, opts) end
    }
  end
end
