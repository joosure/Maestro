defmodule SymphonyElixir.OrchestratorIgnoredMessageTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Orchestrator.IgnoredMessage

  test "fields builds redacted summary for ignored orchestrator messages" do
    fields = IgnoredMessage.fields({:unexpected, %{token: "secret-token", value: "visible"}})

    assert fields.event == :orchestrator_ignored_message
    assert fields.component == "orchestrator"
    assert fields.payload_summary =~ "visible"
    refute fields.payload_summary =~ "secret-token"
  end

  test "log emits ignored orchestrator message" do
    log =
      capture_log([level: :debug], fn ->
        IgnoredMessage.log(:unexpected)
      end)

    assert log =~ "orchestrator_ignored_message"
  end
end
