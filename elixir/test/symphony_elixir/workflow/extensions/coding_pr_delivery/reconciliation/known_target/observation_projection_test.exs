defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.ObservationProjectionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.ObservationProjection

  test "projects reconciliation facts into known-target observation attrs" do
    observed_at = DateTime.from_unix!(1_717_171_717)

    facts =
      Facts.new!(%{
        number: 42,
        url: "https://example.test/pr/42",
        branch: "feature/demo",
        head_sha: "abc123",
        provider_state: :open,
        review_summary: :approved,
        check_summary: :passing,
        mergeability_summary: :mergeable,
        unresolved_actionable_feedback?: false,
        retryable?: false,
        observed_at: observed_at
      })

    attrs = ObservationProjection.attrs(facts)

    assert attrs[Fields.number()] == 42
    assert attrs[Fields.url()] == "https://example.test/pr/42"
    assert attrs[Fields.last_observed_at()] == observed_at
    assert attrs[Fields.last_observed_signature()][Fields.review_summary()] == "approved"
  end
end
