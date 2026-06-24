defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTargetTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields

  test "new rejects non-map attrs with bounded diagnostics" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target",
              reason: :attrs_not_map,
              value_type: "string"
            }} = KnownTarget.new("not-attrs")
  end

  test "new rejects non-keyword opts with bounded diagnostics" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target",
              reason: :opts_not_keyword,
              value_type: "list"
            }} = KnownTarget.new(valid_attrs(), [{"now_ms", 1}])
  end

  test "new rejects invalid durable timestamp opts" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target",
              reason: :invalid_now_ms,
              value_type: "string"
            }} = KnownTarget.new(valid_attrs(), now_ms: "now")
  end

  test "new rejects invalid observed signatures before persistence" do
    attrs = Map.put(valid_attrs(), Fields.last_observed_signature(), %{{:private_key, "secret"} => "value"})

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target",
              reason: {:invalid_last_observed_signature, {:invalid_json_key, :tuple}}
            } = error} = KnownTarget.new(attrs)

    refute inspect(error) =~ "private_key"
    refute inspect(error) =~ "secret"
  end

  test "new derives reference number through Reference when only url is present" do
    attrs =
      valid_attrs()
      |> Map.delete(Fields.number())
      |> Map.put(Fields.url(), "https://example.test/acme/widgets/pulls/42")

    assert {:ok, %KnownTarget{number: "42", url: "https://example.test/acme/widgets/pulls/42"}} =
             KnownTarget.new(attrs, now_ms: 1_000)
  end

  test "merge rejects non-keyword opts and returns merged target on valid opts" do
    {:ok, existing} = KnownTarget.new(valid_attrs(), now_ms: 1_000)
    {:ok, incoming} = KnownTarget.new(Map.put(valid_attrs(), Fields.branch(), "feature/demo"), now_ms: 1_001)

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target",
              reason: :opts_not_keyword
            }} = KnownTarget.merge(existing, incoming, [{"now_ms", 1_002}])

    assert {:ok, %KnownTarget{branch: "feature/demo", updated_at_ms: 1_002}} =
             KnownTarget.merge(existing, incoming, now_ms: 1_002)
  end

  test "merge treats only nil as missing for JSON-compatible signature values" do
    {:ok, existing} =
      valid_attrs()
      |> Map.put(Fields.last_observed_signature(), %{"approved" => true})
      |> KnownTarget.new(now_ms: 1_000)

    {:ok, incoming} =
      valid_attrs()
      |> Map.put(Fields.last_observed_signature(), false)
      |> KnownTarget.new(now_ms: 1_001)

    assert {:ok, %KnownTarget{last_observed_signature: false}} =
             KnownTarget.merge(existing, incoming, now_ms: 1_002)
  end

  defp valid_attrs do
    %{
      Fields.issue_id() => "issue-1",
      Fields.number() => "42",
      Fields.repository() => "acme/widgets"
    }
  end
end
