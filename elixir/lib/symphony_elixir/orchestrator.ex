defmodule SymphonyElixir.Orchestrator do
  @moduledoc """
  Polls the configured tracker and dispatches repository copies to agent-backed workers.
  """

  use GenServer

  alias SymphonyElixir.Orchestrator.AgentUpdates
  alias SymphonyElixir.Orchestrator.IgnoredMessage
  alias SymphonyElixir.Orchestrator.PollCycle
  alias SymphonyElixir.Orchestrator.Polling
  alias SymphonyElixir.Orchestrator.Retry
  alias SymphonyElixir.Orchestrator.Running.Termination
  alias SymphonyElixir.Orchestrator.ServerOptions
  alias SymphonyElixir.Orchestrator.Snapshot
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Orchestrator.TerminalCleanup
  alias SymphonyElixir.Orchestrator.WorkerExit

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = State.initial()
    :ok = TerminalCleanup.run(terminal_cleanup_opts(opts))
    state = PollCycle.schedule_initial_poll(state, opts)

    {:ok, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    _state =
      state.running
      |> Map.keys()
      |> Enum.reduce(state, fn issue_id, state_acc ->
        Termination.terminate_running_issue(state_acc, issue_id, false, ServerOptions.running_opts(state_acc))
      end)

    :ok
  end

  defp terminal_cleanup_opts(opts) when is_list(opts) do
    Keyword.get_lazy(opts, :terminal_cleanup_opts, &ServerOptions.terminal_cleanup_opts/0)
  end

  @impl true
  def handle_info({:tick, tick_token}, %{tick_token: tick_token} = state)
      when is_reference(tick_token) do
    {:noreply, PollCycle.begin(state, ServerOptions.poll_cycle_opts())}
  end

  def handle_info({:tick, _tick_token}, state), do: {:noreply, state}

  def handle_info(:tick, state) do
    {:noreply, PollCycle.begin(state, ServerOptions.poll_cycle_opts())}
  end

  def handle_info(:run_poll_cycle, state) do
    {:noreply, PollCycle.run(state, ServerOptions.poll_cycle_opts())}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %State{} = state
      ) do
    WorkerExit.handle_down_message(state, ref, reason, ServerOptions.worker_exit_opts())
  end

  def handle_info({:worker_runtime_info, issue_id, runtime_info}, state)
      when is_binary(issue_id) and is_map(runtime_info) do
    {:noreply, AgentUpdates.worker_runtime_info(state, issue_id, runtime_info, ServerOptions.agent_update_opts())}
  end

  def handle_info(
        {:agent_worker_update, issue_id, %{event: _, timestamp: _} = update},
        state
      ) do
    {:noreply, AgentUpdates.agent_worker_update(state, issue_id, update, ServerOptions.agent_update_opts())}
  end

  def handle_info({:agent_worker_update, _issue_id, _update}, state), do: {:noreply, state}

  def handle_info({:retry_issue, issue_id, retry_token}, state) do
    Retry.handle_timer_message(state, issue_id, retry_token, ServerOptions.retry_message_opts())
  end

  def handle_info({:retry_issue, _issue_id}, state), do: {:noreply, state}

  def handle_info(msg, state) do
    IgnoredMessage.log(msg)
    {:noreply, state}
  end

  @spec snapshot() :: map() | :timeout | :unavailable
  def snapshot, do: snapshot(__MODULE__, 15_000)

  @spec snapshot(GenServer.server(), timeout()) :: map() | :timeout | :unavailable
  def snapshot(server, timeout) do
    if Process.whereis(server) do
      try do
        GenServer.call(server, :snapshot, timeout)
      catch
        :exit, {:timeout, _} -> :timeout
        :exit, _ -> :unavailable
      end
    else
      :unavailable
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    state = PollCycle.refresh_runtime_config(state)
    {:reply, Snapshot.build(state), state}
  end

  def handle_call(:request_refresh, _from, state) do
    {reply, state} = Polling.request_refresh(state)
    {:reply, reply, state}
  end

  @spec request_refresh() :: map() | :unavailable
  def request_refresh do
    request_refresh(__MODULE__)
  end

  @spec request_refresh(GenServer.server()) :: map() | :unavailable
  def request_refresh(server) do
    if Process.whereis(server) do
      GenServer.call(server, :request_refresh)
    else
      :unavailable
    end
  end
end
