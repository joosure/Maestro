defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfilePreflightCollectTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfilePreflightCollect

  test "is registered as a Coding PR Delivery operator command" do
    assert ProductionProfilePreflightCollect in CodingPrDelivery.operator_commands()
  end

  test "collects a bounded preflight report without raw provider output" do
    test_pid = self()

    deps = %{
      collect_preflight_report: fn plan, opts ->
        send(test_pid, {:collect_preflight_report, plan, opts})

        {:ok,
         %{
           "schema" => "coding_pr_delivery.provider_preflight_report.v1",
           "status" => "blocked",
           "phase2_evidence_plan" => %{"plan_kind" => plan},
           "planned_preflight_command_count" => 2,
           "preflight_result_count" => 2,
           "raw_output_included" => false,
           "does_not_enable_production" => true,
           "provider_preflight_results" => [
             %{
               "template" => "linear_cnb_shadow",
               "command_id" => "linear-tracker-read-only-smoke",
               "status" => "blocked",
               "missing_prerequisites" => ["LINEAR_API_KEY"]
             }
           ]
         }}
      end
    }

    assert {stdout, "", 0} =
             ProductionProfilePreflightCollect.evaluate(
               [
                 "--plan",
                 "linear_cnb_shadow",
                 "--repo",
                 "acme/widgets",
                 "--pr",
                 "7",
                 "--evidence-prefix",
                 "evidence/preflight-smoke",
                 "--json"
               ],
               deps: deps
             )

    payload = Jason.decode!(stdout)

    assert payload["schema"] == "coding_pr_delivery.production_profile_preflight_collect_result.v1"
    assert payload["kind"] == "preflight_report"
    assert payload["status"] == "blocked"
    assert payload["valid"] == true
    assert payload["preflight_report_schema"] == "coding_pr_delivery.provider_preflight_report.v1"
    assert payload["raw_output_included"] == false
    assert payload["does_call_read_only_providers_when_prerequisites_present"] == true
    assert payload["does_not_pass_write_or_destructive_flags"] == true
    assert payload["does_not_enable_production"] == true

    assert_received {:collect_preflight_report, "linear_cnb_shadow", opts}
    assert opts[:repo_slug] == "acme/widgets"
    assert opts[:change_proposal_number] == "7"
    assert opts[:evidence_prefix] == "evidence/preflight-smoke"
  end

  test "returns validation errors without echoing raw input values" do
    deps = %{
      collect_preflight_report: fn _plan, _opts ->
        {:error,
         %{
           code: "coding_pr_delivery_preflight_report_invalid",
           errors: [
             %{
               code: "unknown_plan",
               path: ["plan"],
               message: "Plan is invalid."
             }
           ]
         }}
      end
    }

    assert {stdout, "", 1} =
             ProductionProfilePreflightCollect.evaluate(["--plan", "secret-plan", "--json"], deps: deps)

    payload = Jason.decode!(stdout)

    assert payload["status"] == "invalid"
    assert payload["valid"] == false
    assert payload["preflight_report"] == nil
    assert [%{"code" => "unknown_plan"}] = payload["errors"]
    refute stdout =~ "secret-plan"
  end

  test "does not echo unexpected args, invalid options, or invalid deps" do
    assert {"", unexpected_stderr, 64} =
             ProductionProfilePreflightCollect.evaluate(["secret-extra"], deps: valid_deps())

    assert unexpected_stderr =~ "Unexpected argument count: 1"
    refute unexpected_stderr =~ "secret-extra"

    assert {"", invalid_option_stderr, 64} =
             ProductionProfilePreflightCollect.evaluate(["--secret-option", "secret-value"], deps: valid_deps())

    assert invalid_option_stderr =~ "Invalid option count:"
    refute invalid_option_stderr =~ "--secret-option"
    refute invalid_option_stderr =~ "secret-value"

    assert {"", deps_stderr, 70} = ProductionProfilePreflightCollect.evaluate([], deps: %{secret: true})

    assert deps_stderr =~ "reason=deps_invalid"
    assert deps_stderr =~ "value_type=map"
    refute deps_stderr =~ "secret"
  end

  test "rejects argv lists containing non-strings" do
    assert {"", stderr, 64} = ProductionProfilePreflightCollect.evaluate(["--plan", :secret_plan], deps: valid_deps())

    assert stderr =~ "Command argv must contain only strings"
    assert stderr =~ "value_type=atom"
    refute stderr =~ "secret_plan"
  end

  defp valid_deps do
    %{
      collect_preflight_report: fn _plan, _opts ->
        {:ok,
         %{
           "schema" => "coding_pr_delivery.provider_preflight_report.v1",
           "status" => "blocked",
           "phase2_evidence_plan" => %{"plan_kind" => "tiered_reference"},
           "planned_preflight_command_count" => 0,
           "preflight_result_count" => 0,
           "raw_output_included" => false
         }}
      end
    }
  end
end
