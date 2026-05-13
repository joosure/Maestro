defmodule SymphonyElixir.Orchestrator.Polling do
  @moduledoc false

  @spec begin_poll_check(map()) :: map()
  def begin_poll_check(state) when is_map(state) do
    %{
      state
      | poll_check_in_progress: true,
        next_poll_due_at_ms: nil,
        tick_timer_ref: nil,
        tick_token: nil
    }
  end

  @spec refresh_runtime_config(map(), map()) :: map()
  def refresh_runtime_config(state, config) when is_map(state) and is_map(config) do
    %{
      state
      | poll_interval_ms: config.polling.interval_ms,
        max_concurrent_agents: config.agent.execution.max_concurrent_agents
    }
  end

  def refresh_runtime_config(state, _config), do: state

  @spec request_refresh(map()) :: {map(), map()}
  def request_refresh(state) when is_map(state) do
    now_ms = System.monotonic_time(:millisecond)
    already_due? = is_integer(state.next_poll_due_at_ms) and state.next_poll_due_at_ms <= now_ms
    coalesced = state.poll_check_in_progress == true or already_due?
    state = if coalesced, do: state, else: schedule_tick(state, 0)

    {
      %{
        queued: true,
        coalesced: coalesced,
        requested_at: DateTime.utc_now(),
        operations: ["poll", "reconcile"]
      },
      state
    }
  end

  @spec schedule_tick(map(), integer()) :: map()
  def schedule_tick(state, delay_ms) when is_map(state) and is_integer(delay_ms) and delay_ms >= 0 do
    if is_reference(state.tick_timer_ref) do
      Process.cancel_timer(state.tick_timer_ref)
    end

    tick_token = make_ref()
    timer_ref = Process.send_after(self(), {:tick, tick_token}, delay_ms)

    %{
      state
      | tick_timer_ref: timer_ref,
        tick_token: tick_token,
        next_poll_due_at_ms: System.monotonic_time(:millisecond) + delay_ms
    }
  end

  @spec schedule_poll_cycle_start(non_neg_integer()) :: :ok
  def schedule_poll_cycle_start(delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    :timer.send_after(delay_ms, self(), :run_poll_cycle)
    :ok
  end

  @spec elapsed_ms(integer()) :: non_neg_integer()
  def elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end
end
