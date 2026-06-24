defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.PayloadTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Payload

  test "from_map rejects non-keyword options with bounded diagnostics" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_payload",
              reason: {:invalid_options, :list}
            }} = Payload.from_map(valid_payload(), [{"now_ms", 1}])
  end

  test "from_map rejects non-map payloads with bounded diagnostics" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_payload",
              reason: {:invalid_payload, :string}
            }} = Payload.from_map("not-a-payload")
  end

  test "from_map rejects invalid persisted observed-at values" do
    payload = Map.put(valid_payload(), Fields.last_observed_at(), "not-a-datetime")

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_payload",
              reason: {:invalid_last_observed_at, :invalid_iso8601}
            }} = Payload.from_map(payload)
  end

  test "from_map rejects invalid persisted signatures without dropping the field" do
    payload = Map.put(valid_payload(), Fields.last_observed_signature(), {:not, :json})

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_payload",
              reason: {:invalid_last_observed_signature, {:invalid_json_value, :tuple}}
            }} = Payload.from_map(payload)
  end

  test "signature JSON-key errors do not expose raw keys" do
    target = %KnownTarget{
      issue_id: "issue-1",
      number: "42",
      repository: "acme/widgets",
      last_observed_signature: %{{:private_key, "secret"} => "value"}
    }

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_payload",
              reason: {:invalid_json_key, :tuple}
            } = error} = Payload.to_map(target)

    refute inspect(error) =~ "private_key"
    refute inspect(error) =~ "secret"
  end

  defp valid_payload do
    %{
      Fields.issue_id() => "issue-1",
      Fields.number() => "42",
      Fields.repository() => "acme/widgets"
    }
  end
end
