defmodule SymphonyElixir.Orchestrator.State do
  @moduledoc """
  Runtime state for the orchestrator polling loop.
  """

  alias SymphonyElixir.Config

  @empty_agent_totals %{
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
    seconds_running: 0
  }

  defstruct [
    :poll_interval_ms,
    :max_concurrent_agents,
    :next_poll_due_at_ms,
    :poll_check_in_progress,
    :tick_timer_ref,
    :tick_token,
    running: %{},
    completed: MapSet.new(),
    claimed: MapSet.new(),
    retry_attempts: %{},
    agent_totals: nil,
    agent_rate_limits: nil
  ]

  @type t :: %__MODULE__{
          poll_interval_ms: pos_integer() | nil,
          max_concurrent_agents: pos_integer() | nil,
          next_poll_due_at_ms: integer() | nil,
          poll_check_in_progress: boolean() | nil,
          tick_timer_ref: reference() | nil,
          tick_token: reference() | nil,
          running: map(),
          completed: map(),
          claimed: map(),
          retry_attempts: map(),
          agent_totals: map() | nil,
          agent_rate_limits: map() | nil
        }

  @spec initial(keyword()) :: t()
  def initial(opts \\ []) do
    config = Keyword.get_lazy(opts, :config, &Config.settings!/0)
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)

    %__MODULE__{
      poll_interval_ms: config.polling.interval_ms,
      max_concurrent_agents: config.agent.execution.max_concurrent_agents,
      next_poll_due_at_ms: now_ms,
      poll_check_in_progress: false,
      tick_timer_ref: nil,
      tick_token: nil,
      completed: MapSet.new(),
      claimed: MapSet.new(),
      agent_totals: @empty_agent_totals,
      agent_rate_limits: nil
    }
  end
end
