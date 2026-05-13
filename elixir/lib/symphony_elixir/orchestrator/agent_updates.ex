defmodule SymphonyElixir.Orchestrator.AgentUpdates do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime
  alias SymphonyElixir.Orchestrator.RunningState
  alias SymphonyElixir.Orchestrator.State

  def worker_runtime_info(state, issue_id, runtime_info, opts \\ [])

  @spec worker_runtime_info(State.t(), String.t(), Runtime.worker_runtime_info(), keyword()) :: State.t()
  def worker_runtime_info(%State{running: running} = state, issue_id, runtime_info, opts)
      when is_binary(issue_id) and is_map(runtime_info) do
    case Map.get(running, issue_id) do
      nil ->
        state

      running_entry ->
        running_entry = RunningState.merge_worker_runtime_info(running_entry, runtime_info)

        notify_dashboard(opts)
        %{state | running: Map.put(running, issue_id, running_entry)}
    end
  end

  def worker_runtime_info(%State{} = state, _issue_id, _runtime_info, _opts), do: state

  def agent_worker_update(state, issue_id, update, opts \\ [])

  @spec agent_worker_update(State.t(), String.t(), map(), keyword()) :: State.t()
  def agent_worker_update(%State{running: running} = state, issue_id, %{event: _, timestamp: _} = update, opts)
      when is_binary(issue_id) do
    case Map.get(running, issue_id) do
      nil ->
        state

      running_entry ->
        {running_entry, token_delta} = RunningState.integrate_agent_update(running_entry, update)

        state =
          state
          |> RunningState.apply_token_delta(token_delta)
          |> RunningState.apply_rate_limits(update)

        notify_dashboard(opts)
        %{state | running: Map.put(running, issue_id, running_entry)}
    end
  end

  def agent_worker_update(%State{} = state, _issue_id, _update, _opts), do: state

  defp notify_dashboard(opts) do
    case Keyword.get(opts, :notify_dashboard) do
      notify_dashboard when is_function(notify_dashboard, 0) -> notify_dashboard.()
      _other -> :ok
    end
  end
end
