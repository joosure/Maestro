defmodule SymphonyElixir.Observability.EventContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Observability.EventContract

  test "centralizes canonical event envelope keys and defaults" do
    assert EventContract.timestamp_key() == "timestamp"
    assert EventContract.level_key() == "level"
    assert EventContract.event_key() == "event"
    assert EventContract.message_key() == "message"
    assert EventContract.service_key() == "service"
    assert EventContract.component_key() == "component"
    assert EventContract.result_summary_key() == "result_summary"
    assert EventContract.payload_summary_key() == "payload_summary"
    assert EventContract.error_key() == "error"
    assert EventContract.observability_event_metadata_key() == :observability_event
    assert EventContract.service_name() == "symphony_elixir"
    assert EventContract.unknown_event() == "unknown"
    assert EventContract.unknown_component() == "unknown"
  end
end
