defmodule SymphonyElixir.DynamicToolEventContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.EventContract
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  test "centralizes dynamic tool event atoms, persisted names, and statuses" do
    assert EventContract.event_name(EventContract.tool_call_succeeded_event()) == "tool_call_succeeded"
    assert EventContract.event_atom("tool_call_succeeded") == EventContract.tool_call_succeeded_event()
    assert EventContract.tool_call_succeeded() == "tool_call_succeeded"
    assert EventContract.tool_call_failed() == "tool_call_failed"
    assert EventContract.tool_call_rejected() == "tool_call_rejected"

    assert EventContract.terminal_event_names() == [
             "tool_call_succeeded",
             "tool_call_failed",
             "tool_call_rejected"
           ]

    assert EventContract.status_for_event(:tool_call_succeeded) == EventContract.status_succeeded()
    assert EventContract.status_for_event("tool_call_failed") == EventContract.status_failed()
    assert EventContract.status_for_event("tool_call_rejected") == EventContract.status_rejected()
    assert EventContract.status_for_event("unknown_event") == EventContract.status_failed()
  end

  test "owns dynamic tool observability components and keeps response details in response contract" do
    assert EventContract.dynamic_tool_bridge_component() == "agent.dynamic_tool_bridge"
    assert EventContract.dynamic_tool_failure_policy_component() == "agent.dynamic_tool_failure_policy"
    assert EventContract.typed_tool_failure_policy_blocked() == "typed_tool_failure_policy_blocked"
    assert Response.supported_tools_key() == "supportedTools"
  end
end
