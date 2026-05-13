defmodule SymphonyElixir.AgentUsageTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Orchestrator.AgentUsage

  test "token_delta uses provider-neutral reported token cursors first" do
    running_entry = %{
      agent_last_reported_input_tokens: 10,
      agent_last_reported_output_tokens: 4,
      agent_last_reported_total_tokens: 14
    }

    update = %{
      event: :agent_progress,
      payload: %{usage: %{input_tokens: 12, output_tokens: 7, total_tokens: 19}},
      timestamp: DateTime.utc_now()
    }

    assert AgentUsage.token_delta(running_entry, update) == %{
             input_tokens: 2,
             output_tokens: 3,
             total_tokens: 5,
             input_reported: 12,
             output_reported: 7,
             total_reported: 19
           }
  end

  test "apply_delta and running_seconds stay provider-neutral" do
    totals = %{input_tokens: 1, output_tokens: 2, total_tokens: 3, seconds_running: 4}
    delta = %{input_tokens: 5, output_tokens: 6, total_tokens: 7, seconds_running: 8}

    assert AgentUsage.apply_delta(totals, delta) == %{
             input_tokens: 6,
             output_tokens: 8,
             total_tokens: 10,
             seconds_running: 12
           }

    assert AgentUsage.running_seconds(~U[2026-01-01 00:00:00Z], ~U[2026-01-01 00:00:05Z]) == 5
  end
end
