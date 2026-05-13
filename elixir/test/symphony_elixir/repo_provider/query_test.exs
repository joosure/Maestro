defmodule SymphonyElixir.RepoProvider.QueryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Query

  test "supports field, index, and streamed iteration queries" do
    assert {:ok, "https://example.test/pr/123\n"} =
             Query.run(%{"url" => "https://example.test/pr/123"}, ".url", "CNB")

    assert {:ok, "55\n"} =
             Query.run([%{"id" => 55}, %{"id" => 56}], ".[0].id", "CNB")

    assert {:ok, "55\n56\n"} =
             Query.run([%{"id" => 55}, %{"id" => 56}], ".[].id", "CNB")
  end

  test "rejects unsupported expressions explicitly" do
    assert {:error, %Error{exit_code: 1, message: "Unsupported CNB jq expression: .url // \"\""}} =
             Query.run(%{"url" => "https://example.test/pr/123"}, ".url // \"\"", "CNB")
  end
end
