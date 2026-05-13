defmodule SymphonyElixir.AgentProvider.Codex.EventMappingTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider.Codex.EventMapper
  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper
  alias SymphonyElixir.AgentProvider.Event
  alias SymphonyElixir.AgentProvider.EventSummary
  alias SymphonyElixir.AgentProvider.MessagePresenter

  test "codex event mapper unwraps provider message into canonical event" do
    timestamp = ~U[2026-04-27 08:00:00Z]
    payload = %{"method" => "turn/completed", "session_id" => "session-1"}
    raw = %{event: :notification, message: %{payload: payload}, timestamp: timestamp}

    assert %Event{} = event = EventMapper.map_message(raw)
    assert event.agent_provider_kind == "codex"
    assert event.event == :notification
    assert event.payload == payload
    assert event.raw == raw
    assert event.session_id == "session-1"
    assert event.timestamp == timestamp
  end

  test "codex summary mapper converts canonical event into provider-neutral summary" do
    raw = %{
      event: :turn_failed,
      message: %{
        payload: %{
          "method" => "turn/failed",
          "params" => %{"error" => %{"message" => "rate limited"}}
        }
      }
    }

    assert %EventSummary{} = summary = EventSummaryMapper.summarize(raw)
    assert summary.provider_kind == "codex"
    assert summary.event == :turn_failed
    assert summary.category == :turn
    assert summary.severity == :error
    assert MessagePresenter.present(summary) == "turn failed: rate limited"
  end
end
