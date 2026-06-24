defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ObservationTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Observation

  test "normalizes tuple signature values to lists" do
    signature =
      Observation.signature(%{
        Fields.review_summary() => {:approved, :pending}
      })

    assert signature[Fields.review_summary()] == ["approved", "pending"]
  end
end
