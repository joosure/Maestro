defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileValidateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.{
    ProductionProfilePlan,
    ProductionProfileValidate
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    Phase2ClaimTemplate,
    Phase2EvidencePlan
  }

  test "is registered as a Coding PR Delivery operator command" do
    assert ProductionProfileValidate in CodingPrDelivery.operator_commands()
  end

  test "validates a production claim metadata file without returning the raw packet" do
    assert {:ok, claim} = Phase2ClaimTemplate.build(:linear_cnb_shadow, shadow_run_id: "validate-shadow-1")

    with_json_file!(claim, fn path ->
      assert {stdout, "", 0} =
               ProductionProfileValidate.evaluate(["--kind", "claim", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["schema"] == "coding_pr_delivery.production_profile_validation_result.v1"
      assert payload["kind"] == "claim"
      assert payload["status"] == "valid"
      assert payload["valid"] == true
      assert payload["summary"]["profile_instance_id"] == claim["profile_instance_id"]
      assert payload["summary"]["provider_matrix_entry_ids"] == ["linear-cnb-shadow"]
      assert payload["summary"]["side_effect_modes"] == ["shadow_no_write"]
      assert payload["normalized_packet_included"] == false
      assert payload["raw_input_included"] == false
      assert payload["does_not_call_providers"] == true
      assert payload["does_not_enable_production"] == true
      refute stdout =~ "validate-shadow-1"
    end)
  end

  test "projects review decisions as bounded blocked summaries" do
    with_json_file!(%{"review_packet_id" => "review-packet-secret", "owner_signoffs" => []}, fn path ->
      assert {stdout, "", 0} =
               ProductionProfileValidate.evaluate(["--kind", "review_decision", "--file", path, "--pretty"])

      payload = Jason.decode!(stdout)

      assert payload["kind"] == "review_decision"
      assert payload["status"] == "blocked"
      assert payload["valid"] == false
      assert payload["projection"]["review_packet_id"] == "review-packet-secret"
      assert payload["projection"]["raw_evidence_payload_included"] == false
      assert payload["normalized_packet_included"] == false
      assert payload["does_not_call_providers"] == true
    end)
  end

  test "validates preflight reports as bounded blocker metadata" do
    report = blocked_preflight_report()

    with_json_file!(report, fn path ->
      assert {stdout, "", 0} =
               ProductionProfileValidate.evaluate(["--kind", "preflight_report", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["kind"] == "preflight_report"
      assert payload["status"] == "valid"
      assert payload["valid"] == true
      assert payload["summary"]["status"] == "blocked"
      assert payload["summary"]["phase2_plan_kind"] == "linear_cnb_shadow"
      assert payload["summary"]["planned_preflight_command_count"] == 2
      assert payload["summary"]["preflight_result_count"] == 2
      assert payload["summary"]["raw_output_included"] == false
      assert payload["does_not_call_providers"] == true
      assert payload["does_not_enable_production"] == true
      refute stdout =~ "operator-preflight-shadow"
    end)
  end

  test "returns validation errors without echoing raw packet fields" do
    with_json_file!(%{"profile_instance_id" => "secret-profile"}, fn path ->
      assert {stdout, "", 1} =
               ProductionProfileValidate.evaluate(["--kind", "claim", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["kind"] == "claim"
      assert payload["status"] == "invalid"
      assert payload["valid"] == false
      assert payload["errors"] != []
      refute stdout =~ "secret-profile"
    end)
  end

  test "rejects unknown kinds without echoing the supplied value" do
    with_json_file!(%{}, fn path ->
      assert {"", stderr, 64} =
               ProductionProfileValidate.evaluate(["--kind", "secret-kind", "--file", path])

      assert stderr =~ "Unsupported packet kind"
      refute stderr =~ "secret-kind"
    end)
  end

  test "rejects unreadable or invalid JSON without echoing the file path or contents" do
    unique = System.unique_integer([:positive, :monotonic])
    path = Path.join(System.tmp_dir!(), "secret-packet-#{unique}.json")
    File.write!(path, "{secret-json")

    try do
      assert {"", stderr, 64} =
               ProductionProfileValidate.evaluate(["--kind", "claim", "--file", path])

      assert stderr =~ "Unable to read or parse metadata JSON file"
      refute stderr =~ path
      refute stderr =~ "secret-json"
    after
      File.rm(path)
    end
  end

  test "does not echo unexpected command arguments or invalid options" do
    assert {"", unexpected_stderr, 64} =
             ProductionProfileValidate.evaluate(["--kind", "claim", "--file", "packet.json", "secret-extra"])

    assert unexpected_stderr =~ "Unexpected argument count: 1"
    refute unexpected_stderr =~ "secret-extra"

    assert {"", invalid_stderr, 64} =
             ProductionProfileValidate.evaluate(["--secret-option", "secret-value"])

    assert invalid_stderr =~ "Invalid option count:"
    refute invalid_stderr =~ "--secret-option"
    refute invalid_stderr =~ "secret-value"
  end

  test "rejects invalid deps without leaking raw deps" do
    assert {"", stderr, 70} = ProductionProfileValidate.evaluate([], deps: %{secret: true})

    assert stderr =~ "reason=dependency_invalid"
    assert stderr =~ "value_type=nil"
    refute stderr =~ "secret"
  end

  test "command ids stay distinct" do
    assert ProductionProfileValidate.id() != ProductionProfilePlan.id()
  end

  defp with_json_file!(payload, fun) do
    unique = System.unique_integer([:positive, :monotonic])
    path = Path.join(System.tmp_dir!(), "production-profile-packet-#{unique}.json")
    File.write!(path, Jason.encode!(payload))

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  defp blocked_preflight_report do
    assert {:ok, phase2_plan} =
             Phase2EvidencePlan.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: "operator-preflight-shadow")

    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" =>
        phase2_plan
        |> Map.fetch!("provider_plans")
        |> Enum.flat_map(fn provider_plan ->
          provider_plan
          |> get_in(["read_only_preflight", "commands"])
          |> Enum.map(&preflight_result(Map.fetch!(provider_plan, "template"), &1))
        end),
      "explicit_non_claims" => [
        "preflight_report_does_not_collect_live_provider_evidence",
        "preflight_report_does_not_enable_production"
      ]
    }
  end

  defp preflight_result(template, command) do
    %{
      "template" => template,
      "command_id" => Map.fetch!(command, "id"),
      "target" => Map.fetch!(command, "target"),
      "provider_kind" => Map.fetch!(command, "provider_kind"),
      "status" => "blocked",
      "blocker_code" => "missing_preflight_prerequisite",
      "missing_prerequisites" => [first_prerequisite(command)],
      "ran_at" => "2026-06-26T03:20:00Z",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false
    }
  end

  defp first_prerequisite(command) do
    command
    |> Map.take(["required_env", "required_auth", "required_targets"])
    |> Map.values()
    |> Enum.flat_map(fn
      values when is_list(values) -> values
      _value -> []
    end)
    |> List.first()
  end
end
