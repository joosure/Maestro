defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ToolResultRecorderTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ToolResultRecorder

  test "uses stable extension-owned tracker recorder id" do
    assert ToolResultRecorder.id() == CodingPrDelivery.id() <> ".tracker_tool_result"
  end

  test "ignores non-tracker source kinds without interpreting payload" do
    assert :ok =
             ToolResultRecorder.record_tool_result(
               :repo,
               %{secret: "should-not-be-read"},
               "repo.tool",
               %{secret: "should-not-be-read"},
               {:success, %{secret: "should-not-be-read"}},
               [:not_keyword]
             )
  end

  test "accepts tracker source kind as atom or string" do
    assert :ok =
             ToolResultRecorder.record_tool_result(
               :tracker,
               %{},
               "tracker.tool",
               %{},
               {:failure, :ignored_by_handler},
               []
             )

    assert :ok =
             ToolResultRecorder.record_tool_result(
               "tracker",
               %{},
               "tracker.tool",
               %{},
               {:failure, :ignored_by_handler},
               []
             )
  end

  test "fails closed for tracker results with non-keyword options" do
    assert {:error,
            %{
              code: code,
              message: "Coding PR Delivery tool-result recorder options are invalid.",
              reason: :options_not_keyword,
              value_type: "list"
            }} =
             ToolResultRecorder.record_tool_result(
               :tracker,
               %{secret: "should-not-leak"},
               "tracker.tool",
               %{secret: "should-not-leak"},
               {:success, %{secret: "should-not-leak"}},
               [:not_keyword]
             )

    assert code == ErrorCodes.invalid_tool_result_recorder()
  end

  test "fails closed for tracker results with non-list options" do
    assert {:error,
            %{
              code: code,
              reason: :options_not_keyword,
              value_type: "map"
            }} =
             ToolResultRecorder.record_tool_result(
               "tracker",
               %{},
               "tracker.tool",
               %{},
               {:failure, :ignored_by_handler},
               %{not: "keyword"}
             )

    assert code == ErrorCodes.invalid_tool_result_recorder()
  end
end
