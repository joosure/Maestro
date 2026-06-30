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

  test "to_map and from_map round-trip Linear + CNB provider identity without raw payloads" do
    attrs = Map.put(linear_cnb_payload(), "raw_provider_payload", %{"authorization" => "Bearer secret-token"})

    {:ok, target} = KnownTarget.new(attrs, now_ms: 1_000)

    assert {:ok, payload} = Payload.to_map(target)
    assert payload[Fields.issue_id()] == "LIN-42"
    assert payload[Fields.tracker_kind()] == "linear"
    assert payload[Fields.repo_provider_kind()] == "cnb"
    assert payload[Fields.repository()] == "cnb/acme/widgets"
    assert payload[Fields.number()] == "42"
    assert payload[Fields.url()] == "https://cnb.cool/acme/widgets/-/merge_requests/42"
    assert payload[Fields.branch()] == "feature/linear-cnb-shadow"
    assert payload[Fields.head_sha()] == "abc123"
    refute Map.has_key?(payload, "raw_provider_payload")
    refute inspect(payload) =~ "secret-token"

    assert {:ok,
            %KnownTarget{
              issue_id: "LIN-42",
              tracker_kind: "linear",
              repo_provider_kind: "cnb",
              repository: "cnb/acme/widgets",
              number: "42",
              url: "https://cnb.cool/acme/widgets/-/merge_requests/42",
              branch: "feature/linear-cnb-shadow",
              head_sha: "abc123"
            }} = Payload.from_map(payload, now_ms: 2_000)
  end

  defp valid_payload do
    %{
      Fields.issue_id() => "issue-1",
      Fields.number() => "42",
      Fields.repository() => "acme/widgets"
    }
  end

  defp linear_cnb_payload do
    %{
      Fields.issue_id() => "LIN-42",
      Fields.tracker_kind() => "linear",
      Fields.repo_provider_kind() => "cnb",
      Fields.repository() => "cnb/acme/widgets",
      Fields.number() => "42",
      Fields.url() => "https://cnb.cool/acme/widgets/-/merge_requests/42",
      Fields.branch() => "feature/linear-cnb-shadow",
      Fields.head_sha() => "abc123"
    }
  end
end
