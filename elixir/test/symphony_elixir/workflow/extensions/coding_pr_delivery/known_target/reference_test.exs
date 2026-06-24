defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ReferenceTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ReferenceExtractor

  test "reference accepts canonical change proposal fields" do
    assert %Reference{number: "42", url: "https://example.test/pr/42", branch: "feature/demo"} =
             Reference.from_map(%{
               "number" => 42,
               "url" => "https://example.test/pr/42",
               "branch" => "feature/demo"
             })
  end

  test "reference derives number from url when explicit number is absent" do
    assert %Reference{number: "42", url: "https://example.test/acme/widgets/pulls/42"} =
             Reference.from_map(%{
               "url" => "https://example.test/acme/widgets/pulls/42"
             })
  end

  test "reference extractor accepts canonical workflow metadata and branch fallback" do
    issue = %{
      "branch_name" => "feature/fallback",
      "workflow" => %{
        "change_proposal" => %{
          "number" => 43,
          "url" => "https://example.test/pr/43"
        }
      }
    }

    assert %Reference{number: "43", url: "https://example.test/pr/43", branch: "feature/fallback"} =
             ReferenceExtractor.from_issue(issue)
  end

  test "reference extractor accepts issue structs without depending on the issue module" do
    issue = %Issue{
      branch_name: "feature/struct-fallback",
      workflow: %{
        "change_proposal" => %{
          "number" => "44",
          "url" => "https://example.test/pr/44"
        }
      }
    }

    assert %Reference{number: "44", url: "https://example.test/pr/44", branch: "feature/struct-fallback"} =
             ReferenceExtractor.from_issue(issue)
  end
end
