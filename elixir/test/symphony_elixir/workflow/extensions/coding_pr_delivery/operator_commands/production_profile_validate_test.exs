defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileValidateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.{
    ProductionProfilePlan,
    ProductionProfileValidate
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplate

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
end
