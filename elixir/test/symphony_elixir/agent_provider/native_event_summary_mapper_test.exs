defmodule SymphonyElixir.AgentProvider.NativeEventSummaryMapperTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.EventSummary

  test "claude_code summary mapper formats assistant parts" do
    reasoning = %{
      agent_provider_kind: "claude_code",
      event: "message.part.updated",
      payload: %{
        "payload" => %{
          "type" => "message.part.updated",
          "properties" => %{
            "part" => %{"type" => "reasoning", "text" => "checking files\nbefore editing"}
          }
        }
      }
    }

    assert %EventSummary{} = summary = AgentProvider.summarize_message(reasoning)
    assert summary.provider_kind == "claude_code"
    assert summary.category == :message
    assert summary.text == "reasoning update: checking files before editing"

    tool = %{
      agent_provider_kind: "claude_code",
      event: "message.part.updated",
      payload: %{
        "payload" => %{
          "type" => "message.part.updated",
          "properties" => %{
            "part" => %{"type" => "tool", "tool" => "Read", "state" => %{"status" => "running"}}
          }
        }
      }
    }

    assert AgentProvider.summarize_message(tool).category == :tool
    assert AgentProvider.present_message(tool) == "tool running (Read)"
  end

  test "claude_code summary mapper formats turn completion usage" do
    message = %{
      agent_provider_kind: "claude_code",
      event: :turn_completed,
      payload: %{"type" => "result"},
      usage: %{input: 8, output: 3, reasoning: 2, total: 13}
    }

    assert AgentProvider.present_message(message) == "turn completed (in 8, out 3, reasoning 2, total 13)"
  end

  test "opencode summary mapper formats permission and usage events" do
    permission = %{
      agent_provider_kind: "opencode",
      event: "permission.asked",
      payload: %{
        "event" => "permission.asked",
        "payload" => %{
          "payload" => %{
            "type" => "permission.asked",
            "properties" => %{"permission" => "edit", "patterns" => ["."]}
          }
        }
      }
    }

    assert %EventSummary{} = permission_summary = AgentProvider.summarize_message(permission)
    assert permission_summary.provider_kind == "opencode"
    assert permission_summary.category == :approval
    assert permission_summary.text == "permission requested (edit: .)"

    step_finished = %{
      agent_provider_kind: "opencode",
      event: "message.part.updated",
      payload: %{
        "payload" => %{
          "type" => "message.part.updated",
          "properties" => %{
            "part" => %{"type" => "step-finish", "tokens" => %{"input" => 1, "output" => 2, "reasoning" => 3}}
          }
        }
      }
    }

    assert AgentProvider.summarize_message(step_finished).category == :usage
    assert AgentProvider.present_message(step_finished) == "step completed (in 1, out 2, reasoning 3)"
  end
end
