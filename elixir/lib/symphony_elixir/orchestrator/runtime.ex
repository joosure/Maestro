defmodule SymphonyElixir.Orchestrator.Runtime do
  @moduledoc false

  alias SymphonyElixir.Config
  alias SymphonyElixir.Config.Capabilities, as: ConfigCapabilities
  alias SymphonyElixir.Orchestrator.Events
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Orchestrator.WorkerHosts
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig

  @spec dispatch_context() :: map()
  def dispatch_context do
    settings = Config.settings!()
    tracker_config = settings.tracker

    SymphonyElixir.Orchestrator.Dispatch.new_context(
      TrackerConfig.active_states(tracker_config),
      TrackerConfig.terminal_states(tracker_config),
      state_phase_map: TrackerConfig.state_phase_map(tracker_config) || %{},
      workflow_settings: workflow_settings(settings),
      available_capabilities: ConfigCapabilities.available_capabilities(settings),
      max_concurrent_agents_for_state: &Config.max_concurrent_agents_for_state/1
    )
  end

  @spec dispatch_runtime(State.t()) :: map()
  def dispatch_runtime(%State{} = state), do: dispatch_runtime(state, nil)

  @spec dispatch_runtime(State.t(), String.t() | nil) :: map()
  def dispatch_runtime(%State{} = state, preferred_worker_host) do
    %{
      running: state.running,
      claimed: state.claimed,
      orchestrator_slots: Events.available_slots(state),
      worker_slots_available?: WorkerHosts.slots_available?(state, preferred_worker_host)
    }
  end

  @spec agent_provider_timeout_option(String.t(), non_neg_integer()) :: non_neg_integer()
  def agent_provider_timeout_option(key, default) when is_binary(key) and is_integer(default) do
    case Config.agent_provider_option(key) do
      value when is_integer(value) and value >= 0 -> value
      _other -> default
    end
  end

  @spec running_poll_interval_ms(State.t() | map() | nil, integer()) :: integer()
  def running_poll_interval_ms(%State{poll_interval_ms: poll_interval_ms}, _default_ms)
      when is_integer(poll_interval_ms) and poll_interval_ms > 0,
      do: poll_interval_ms

  def running_poll_interval_ms(%{poll_interval_ms: poll_interval_ms}, _default_ms)
      when is_integer(poll_interval_ms) and poll_interval_ms > 0,
      do: poll_interval_ms

  def running_poll_interval_ms(_state, default_ms) when is_integer(default_ms), do: default_ms

  defp workflow_settings(settings) when is_map(settings) do
    %{
      workflow: Map.get(settings, :workflow),
      tracker: %{
        lifecycle: settings |> Map.get(:tracker) |> TrackerConfig.lifecycle()
      }
    }
  end
end
