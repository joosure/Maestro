defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileStatusTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileStatus

  test "is registered as a Coding PR Delivery operator command" do
    assert ProductionProfileStatus in CodingPrDelivery.operator_commands()
  end

  test "exports a bounded status report for the default Phase 2 plan" do
    assert {stdout, "", 0} = ProductionProfileStatus.evaluate(["--plan", "linear_cnb_shadow", "--json"])

    payload = Jason.decode!(stdout)

    assert payload["schema"] == "coding_pr_delivery.production_profile_status.v1"
    assert payload["status"] == "blocked"
    assert payload["phase4_ready"] == false
    assert payload["preflight"]["provided"] == false
    assert payload["does_not_read_evidence_files"] == true
    assert payload["does_not_call_providers"] == true
    assert payload["does_not_enable_production"] == true
    assert Enum.any?(payload["blockers"], &(&1["code"] == "provider_preflight_report_required"))
  end

  test "merges preflight report files without reading referenced evidence" do
    phase2_plan = phase2_plan()
    preflight_report = passed_preflight_report(phase2_plan)

    deps = %{
      read_file: fn
        "phase2.json" -> {:ok, Jason.encode!(phase2_plan)}
        "preflight.json" -> {:ok, Jason.encode!(preflight_report)}
      end,
      production_status: fn input, opts ->
        SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.production_status(input, opts)
      end
    }

    assert {stdout, "", 0} =
             ProductionProfileStatus.evaluate(
               ["--phase2-plan-file", "phase2.json", "--preflight-report-file", "preflight.json", "--pretty"],
               deps: deps
             )

    payload = Jason.decode!(stdout)

    assert payload["preflight"]["provided"] == true
    assert payload["preflight"]["status"] == "passed"
    refute Enum.any?(payload["blockers"], &(&1["code"] == "provider_preflight_report_required"))
    assert Enum.any?(payload["blockers"], &(&1["code"] == "completed_evidence_packet_required"))
  end

  test "does not echo unreadable file paths or raw input" do
    deps = %{read_file: fn _path -> {:error, :enoent} end, production_status: fn _input, _opts -> flunk("status should not run") end}

    assert {"", stderr, 64} =
             ProductionProfileStatus.evaluate(["--phase2-plan-file", "secret-phase2.json"], deps: deps)

    assert stderr =~ "Phase 2 plan file could not be read or parsed."
    refute stderr =~ "secret-phase2"
  end

  test "rejects invalid command shapes without leaking arguments or deps" do
    assert {"", stderr, 64} = ProductionProfileStatus.evaluate(["--plan", :secret_plan])

    assert stderr =~ "Command argv must contain only strings"
    assert stderr =~ "value_type=atom"
    refute stderr =~ "secret_plan"

    assert {"", deps_stderr, 70} = ProductionProfileStatus.evaluate([], deps: %{secret: true})

    assert deps_stderr =~ "reason=deps_invalid"
    assert deps_stderr =~ "value_type=map"
    refute deps_stderr =~ "secret"
  end

  defp phase2_plan do
    assert {:ok, plan} =
             SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.phase2_evidence_plan(:linear_cnb_shadow)

    plan
  end

  defp passed_preflight_report(phase2_plan) do
    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => preflight_results(phase2_plan),
      "explicit_non_claims" => ["preflight_report_does_not_enable_production"]
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
          "ran_at" => "2026-06-26T00:00:00Z",
          "side_effect_mode" => "read_only",
          "write_performed" => false,
          "production_enabled" => false,
          "missing_prerequisites" => [],
          "evidence_files" => ["evidence/preflight/#{Map.fetch!(command, "id")}.md"]
        }
      end)
    end)
  end
end
