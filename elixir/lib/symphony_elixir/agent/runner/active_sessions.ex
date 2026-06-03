defmodule SymphonyElixir.Agent.Runner.ActiveSessions do
  @moduledoc false

  use GenServer

  alias SymphonyElixir.Agent.Runner.{EventFields, ProviderOptions, SessionCleanup}
  alias SymphonyElixir.AgentProvider

  @type cleanup_context :: %{
          optional(:issue) => term(),
          optional(:worker_host) => String.t() | nil,
          optional(:workspace) => Path.t() | nil,
          optional(:run_id) => String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec register(term(), cleanup_context(), GenServer.server()) :: :ok
  def register(session, context, server \\ __MODULE__) when is_map(context) do
    call_if_running(server, {:register, self(), session, context})
  end

  @spec claim_current_cleanup(GenServer.server()) :: :ok | :not_registered | :unavailable
  def claim_current_cleanup(server \\ __MODULE__) do
    call_cleanup_if_running(server, {:claim_current_cleanup, self()})
  end

  @spec cleanup_owner(pid(), term(), GenServer.server()) :: :ok
  def cleanup_owner(owner, reason \\ :shutdown, server \\ __MODULE__) when is_pid(owner) do
    call_if_running(server, {:cleanup_owner, owner, reason}, 10_000)
  end

  @impl true
  def init(_state) do
    Process.flag(:trap_exit, true)
    {:ok, %{entries: %{}}}
  end

  @impl true
  def handle_call({:register, owner, session, context}, _from, state) when is_pid(owner) do
    state = remove_owner(state, owner)
    monitor_ref = Process.monitor(owner)
    entry = %{owner: owner, monitor_ref: monitor_ref, session: session, context: context}
    {:reply, :ok, put_in(state, [:entries, owner], entry)}
  end

  def handle_call({:claim_current_cleanup, owner}, _from, state) when is_pid(owner) do
    case pop_owner(state, owner) do
      {nil, state} ->
        {:reply, :not_registered, state}

      {_entry, state} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:cleanup_owner, owner, reason}, _from, state) when is_pid(owner) do
    {entry, state} = pop_owner(state, owner)
    cleanup_entry(entry, reason)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, owner, reason}, state) do
    case Map.get(state.entries, owner) do
      %{monitor_ref: ^monitor_ref} = entry ->
        cleanup_entry(entry, reason)
        {:noreply, %{state | entries: Map.delete(state.entries, owner)}}

      _entry ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    state
    |> Map.get(:entries, %{})
    |> Map.values()
    |> Enum.each(&cleanup_entry(&1, reason))

    :ok
  end

  defp call_if_running(server, request, timeout \\ 5_000) do
    case resolve_server(server) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        GenServer.call(pid, request, timeout)
    end
  catch
    :exit, _reason -> :ok
  end

  defp call_cleanup_if_running(server, request) do
    case resolve_server(server) do
      nil ->
        :unavailable

      pid when is_pid(pid) ->
        GenServer.call(pid, request, 10_000)
    end
  catch
    :exit, _reason -> :unavailable
  end

  defp resolve_server(server) when is_atom(server), do: Process.whereis(server)
  defp resolve_server(server) when is_pid(server), do: server
  defp resolve_server(_server), do: nil

  defp remove_owner(state, owner) do
    {_entry, state} = pop_owner(state, owner)
    state
  end

  defp pop_owner(%{entries: entries} = state, owner) do
    case Map.pop(entries, owner) do
      {nil, entries} ->
        {nil, %{state | entries: entries}}

      {%{monitor_ref: monitor_ref} = entry, entries} ->
        Process.demonitor(monitor_ref, [:flush])
        {entry, %{state | entries: entries}}
    end
  end

  defp cleanup_entry(nil, _reason), do: :ok

  defp cleanup_entry(%{session: session, context: context}, reason) do
    issue = Map.get(context, :issue)
    worker_host = Map.get(context, :worker_host)
    workspace = Map.get(context, :workspace)
    run_id = Map.get(context, :run_id) || EventFields.session_value(session, :run_id) || "unknown-run"

    stop_opts =
      if graceful_owner_down?(reason) do
        SessionCleanup.stop_options(session, :ok, issue)
      else
        AgentProvider.failed_session_stop_options(
          issue || %{},
          inspect(reason),
          ProviderOptions.from_session(session)
        )
      end

    _ = SessionCleanup.stop(session, stop_opts, issue || Keyword.get(stop_opts, :issue) || %{}, worker_host, workspace, run_id, "owner_down")
    :ok
  end

  defp graceful_owner_down?(:normal), do: true
  defp graceful_owner_down?(:shutdown), do: true
  defp graceful_owner_down?({:shutdown, _reason}), do: true
  defp graceful_owner_down?(:running_issue_terminated), do: true
  defp graceful_owner_down?(_reason), do: false
end
