defmodule SymphonyElixir.Observability.FormatterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Observability.Formatter

  test "formats canonical observability events as JSON lines" do
    payload = %{
      "timestamp" => "2026-04-20T00:00:00.000Z",
      "level" => "info",
      "event" => "tool_call_requested",
      "message" => "tool_call_requested",
      "service" => "symphony_elixir",
      "component" => "agent.dynamic_tool_bridge",
      "issue_id" => "issue-123",
      "session_id" => "thread-1-turn-1"
    }

    event = %{
      level: :info,
      msg: {"tool_call_requested", []},
      meta: %{
        time: System.system_time(:microsecond),
        observability_event: payload
      }
    }

    line =
      event
      |> Formatter.format(%{})
      |> IO.iodata_to_binary()

    assert String.ends_with?(line, "\n")
    assert Jason.decode!(line) == payload
  end

  test "formats generic logger events into redacted JSON lines" do
    event = %{
      level: :error,
      msg: {"LINEAR_API_KEY=secret-token request failed", []},
      meta: %{
        time: System.system_time(:microsecond),
        component: "tracker.linear.client",
        request_id: "req-123",
        correlation_id: "corr-123",
        run_id: "run-123",
        issue_id: "issue-456",
        session_id: "thread-2-turn-2",
        event: :tracker_request_failed,
        status: 500
      }
    }

    payload =
      event
      |> Formatter.format(%{})
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert payload["event"] == "tracker_request_failed"
    assert payload["component"] == "tracker.linear.client"
    assert payload["request_id"] == "req-123"
    assert payload["correlation_id"] == "corr-123"
    assert payload["run_id"] == "run-123"
    assert payload["issue_id"] == "issue-456"
    assert payload["session_id"] == "thread-2-turn-2"
    assert payload["status"] == 500
    assert payload["level"] == "error"
    assert payload["message"] =~ "LINEAR_API_KEY=[REDACTED]"
    refute payload["message"] =~ "secret-token"
  end

  test "formats generic logger events with structured messages" do
    event = %{
      level: :debug,
      msg: %{
        "arguments" => %{
          "body" => "## Claude Code Workpad",
          "api_key" => "secret-token"
        },
        "tool" => "linear_upsert_workpad"
      },
      meta: %{
        time: System.system_time(:microsecond),
        component: "phoenix",
        event: :log_message,
        request_id: "req-456"
      }
    }

    payload =
      event
      |> Formatter.format(%{})
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert payload["event"] == "log_message"
    assert payload["component"] == "phoenix"
    assert payload["request_id"] == "req-456"
    assert payload["message"] =~ "linear_upsert_workpad"
    assert payload["message"] =~ "Claude Code Workpad"
    refute payload["message"] =~ "secret-token"
    refute payload["event"] == "formatter_failed"
  end

  test "redacts canonical observability events before JSON encoding" do
    event = %{
      level: :info,
      msg: {"tool_call_requested", []},
      meta: %{
        time: System.system_time(:microsecond),
        observability_event: %{
          "timestamp" => "2026-04-20T00:00:00.000Z",
          "level" => "info",
          "event" => "tool_call_requested",
          "message" => "tool_call_requested authorization=Bearer secret",
          "service" => "symphony_elixir",
          "component" => "agent.dynamic_tool_bridge",
          "access_token" => "secret",
          "total_tokens" => 12
        }
      }
    }

    payload =
      event
      |> Formatter.format(%{})
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert payload["access_token"] == "[REDACTED]"
    assert payload["message"] =~ "authorization=[REDACTED]"
    assert payload["total_tokens"] == 12
    refute payload["message"] =~ "secret"
  end
end
