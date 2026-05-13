defmodule SymphonyElixir.OrchestratorStateTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Orchestrator.State

  test "initial builds orchestrator runtime defaults from config" do
    config = %{
      polling: %{interval_ms: 12_345},
      agent: %{execution: %{max_concurrent_agents: 7}}
    }

    assert %State{} = state = State.initial(config: config, now_ms: 123)
    assert state.poll_interval_ms == 12_345
    assert state.max_concurrent_agents == 7
    assert state.next_poll_due_at_ms == 123
    assert state.poll_check_in_progress == false
    assert state.tick_timer_ref == nil
    assert state.tick_token == nil
    assert state.running == %{}
    assert state.completed == MapSet.new()
    assert state.claimed == MapSet.new()
    assert state.retry_attempts == %{}

    assert state.agent_totals == %{
             input_tokens: 0,
             output_tokens: 0,
             total_tokens: 0,
             seconds_running: 0
           }

    assert state.agent_rate_limits == nil
  end
end
