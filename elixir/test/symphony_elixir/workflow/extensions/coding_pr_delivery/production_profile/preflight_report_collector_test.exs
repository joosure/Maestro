defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReportCollectorTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.PreflightReportCollector

  @fixed_now ~U[2026-06-26 05:45:00Z]

  test "records missing prerequisites without calling providers" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:tiered_reference)

    deps = %{
      env: fn -> %{} end,
      utc_now: fn -> @fixed_now end,
      tracker_smoke: fn _argv -> flunk("tracker smoke must not run when prerequisites are missing") end,
      repo_provider_smoke: fn _argv -> flunk("repo-provider smoke must not run when prerequisites are missing") end
    }

    assert {:ok, report} = PreflightReportCollector.collect(phase2_plan, [], deps)

    assert report["schema"] == "coding_pr_delivery.provider_preflight_report.v1"
    assert report["status"] == "blocked"
    assert report["planned_preflight_command_count"] == 6
    assert report["preflight_result_count"] == 6
    assert report["raw_output_included"] == false
    assert report["does_not_enable_production"] == true

    assert Enum.all?(report["provider_preflight_results"], &(&1["status"] == "blocked"))
    assert Enum.all?(report["provider_preflight_results"], &(&1["side_effect_mode"] == "read_only"))
    assert Enum.all?(report["provider_preflight_results"], &(&1["write_performed"] == false))
    assert Enum.all?(report["provider_preflight_results"], &(&1["production_enabled"] == false))
  end

  test "runs only read-only smoke commands when prerequisites are present" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_cnb_shadow)

    test_pid = self()

    deps = %{
      env: fn ->
        %{
          env_key(["LINEAR", "API", "KEY"]) => "linear-config-present",
          env_key(["LINEAR", "PROJECT", "SLUG"]) => "linear-project-present",
          env_key(["CNB", "TOKEN"]) => "cnb-config-present"
        }
      end,
      utc_now: fn -> @fixed_now end,
      tracker_smoke: fn argv ->
        send(test_pid, {:tracker_smoke, argv})
        {Jason.encode!(%{"ok" => true}), "", 0}
      end,
      repo_provider_smoke: fn argv ->
        send(test_pid, {:repo_provider_smoke, argv})
        {Jason.encode!(%{"ok" => true}), "", 0}
      end
    }

    assert {:ok, report} =
             PreflightReportCollector.collect(
               phase2_plan,
               [
                 repo_slug: "acme/widgets",
                 change_proposal_number: "7",
                 evidence_prefix: "evidence/preflight-smoke"
               ],
               deps
             )

    assert report["status"] == "passed"
    assert Enum.all?(report["provider_preflight_results"], &(&1["status"] == "passed"))
    assert Enum.all?(report["provider_preflight_results"], &(List.first(&1["evidence_files"]) =~ "evidence/preflight-smoke/"))

    assert_received {:tracker_smoke, ["--template", "linear/github/opencode", "--json"]}
    assert_received {:repo_provider_smoke, ["--provider", "cnb", "--repo", "acme/widgets", "--pr", "7", "--json"]}
  end

  test "blocks failed smoke without storing raw provider output" do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_github_ready)

    deps = %{
      env: fn ->
        %{
          env_key(["LINEAR", "API", "KEY"]) => "linear-config-present",
          env_key(["LINEAR", "PROJECT", "SLUG"]) => "linear-project-present"
        }
      end,
      utc_now: fn -> @fixed_now end,
      tracker_smoke: fn _argv -> {Jason.encode!(%{"ok" => true}), "", 0} end,
      repo_provider_smoke: fn _argv -> {"secret raw stdout", "secret raw stderr", 1} end
    }

    assert {:ok, report} =
             PreflightReportCollector.collect(
               phase2_plan,
               [repo_slug: "joosure/Maestro", change_proposal_number: "18"],
               deps
             )

    assert report["status"] == "blocked"

    github_result =
      Enum.find(report["provider_preflight_results"], &(&1["command_id"] == "github-repo-provider-read-only-smoke"))

    assert github_result["status"] == "blocked"
    assert github_result["blocker_code"] == "preflight_smoke_failed"
    assert "gh auth status" in github_result["missing_prerequisites"]
    refute inspect(report) =~ "secret raw stdout"
    refute inspect(report) =~ "secret raw stderr"
  end

  defp env_key(parts), do: Enum.join(parts, "_")
end
