defmodule SymphonyWorkerDaemon.Session.Server do
  @moduledoc false

  use GenServer

  alias SymphonyWorkerDaemon.{BridgeProxy, CapacityManager, CommandPolicy, ProcessRunner, WorkspaceManager}
  alias SymphonyWorkerDaemon.Session.Ledger
  alias SymphonyWorkerDaemon.Session.Server.{Events, Options, Payloads, ProviderEnvironment, Request, RequestFingerprint, ResourceBudget, Status, TimeoutPolicy}

  @type status :: String.t()

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :session_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    registry = Keyword.get(opts, :registry, SymphonyWorkerDaemon.SessionRegistry)
    GenServer.start_link(__MODULE__, opts, name: via(registry, session_id))
  end

  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :session_not_found}
  def lookup(session_id) when is_binary(session_id), do: lookup(SymphonyWorkerDaemon.SessionRegistry, session_id)

  @spec lookup(module(), String.t()) :: {:ok, pid()} | {:error, :session_not_found}
  def lookup(registry, session_id) when is_binary(session_id) do
    case Registry.lookup(registry, session_id) do
      [{pid, _value} | _rest] -> {:ok, pid}
      [] -> {:error, :session_not_found}
    end
  end

  @spec send_input(GenServer.server(), iodata()) :: :ok | {:error, term()}
  def send_input(server, data), do: GenServer.call(server, {:send_input, IO.iodata_to_binary(data)})

  @spec status(GenServer.server()) :: map()
  def status(server), do: GenServer.call(server, :status)

  @spec summary(GenServer.server()) :: map()
  def summary(server), do: GenServer.call(server, :summary)

  @spec request_matches?(GenServer.server(), map()) :: boolean()
  def request_matches?(server, request) when is_map(request), do: GenServer.call(server, {:request_matches?, RequestFingerprint.fingerprint(request)})

  @spec events(GenServer.server(), keyword()) :: [map()]
  def events(server, opts \\ []) when is_list(opts), do: GenServer.call(server, {:events, opts})

  @spec stop_session(GenServer.server(), keyword()) :: :ok
  def stop_session(server, opts \\ []), do: GenServer.call(server, {:stop_session, opts})

  @spec cleanup(GenServer.server(), keyword()) :: :ok
  def cleanup(server, opts \\ []), do: GenServer.call(server, {:cleanup, opts})

  @impl true
  @spec init(keyword()) :: {:ok, map()} | {:stop, term()}
  def init(opts) when is_list(opts) do
    request = Keyword.fetch!(opts, :request)
    session_id = Keyword.fetch!(opts, :session_id)
    capacity_manager = Keyword.get(opts, :capacity_manager)
    workspace_roots = Keyword.get(opts, :workspace_roots, [])
    runner = Keyword.get(opts, :process_runner, ProcessRunner)
    now_ms = System.system_time(:millisecond)

    with {:ok, cwd} <- WorkspaceManager.validate_workspace(Request.workspace(request), workspace_roots: workspace_roots),
         :ok <- CommandPolicy.validate(Request.command(request), cwd, Options.command_policy(opts)),
         {:ok, lease_id} <- admit(capacity_manager, session_id, request) do
      start_provider_process(%{
        opts: opts,
        request: request,
        session_id: session_id,
        lease_id: lease_id,
        cwd: cwd,
        runner: runner,
        capacity_manager: capacity_manager,
        now_ms: now_ms
      })
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()} | {:stop, term(), term(), map()}
  def handle_call({:send_input, data}, _from, %{status: "running", port: port} = state) when is_binary(data) do
    true = Port.command(port, data)
    {:reply, :ok, note_client_activity(state)}
  rescue
    ArgumentError -> {:reply, {:error, :session_not_running}, state}
  end

  def handle_call({:send_input, _data}, _from, state), do: {:reply, {:error, :session_not_running}, state}

  def handle_call(:status, _from, state), do: {:reply, Payloads.status(state), state}
  def handle_call(:summary, _from, state), do: {:reply, Payloads.summary(state), state}
  def handle_call({:request_matches?, fingerprint}, _from, state), do: {:reply, Map.get(state, :request_fingerprint) == fingerprint, state}
  def handle_call({:events, opts}, _from, state), do: {:reply, Events.event_window(state, opts), state}

  def handle_call({:stop_session, opts}, _from, state) do
    {:reply, :ok, stop_running_process(state, opts)}
  end

  def handle_call({:cleanup, opts}, _from, state) do
    state = stop_running_process(state, opts)
    _cleanup_result = WorkspaceManager.cleanup_workspace(state.cwd, opts)

    state =
      state
      |> stop_bridge_proxy_once()
      |> release_capacity_once()

    cleaned_state =
      state
      |> Map.put(:status, "cleaned")
      |> Map.put(:updated_at_ms, System.system_time(:millisecond))
      |> record_ledger()

    {:stop, :normal, :ok, cleaned_state}
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state),
    do: {:noreply, state |> note_provider_output() |> Events.append_output("stdout", IO.iodata_to_binary(chunk) <> "\n")}

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state),
    do: {:noreply, state |> note_provider_output() |> Events.append_output("stdout", IO.iodata_to_binary(chunk))}

  def handle_info({port, {:exit_status, _status}}, %{port: port, status: status} = state)
      when status in ["exited", "failed", "cleaned", "stopped", "lost"],
      do: {:noreply, state}

  def handle_info({port, {:exit_status, status}}, %{port: port} = state), do: {:noreply, mark_exit_status(state, status)}

  def handle_info({:session_timeout, token}, %{session_timeout_ref: {_timer_ref, token}, status: "running"} = state),
    do: {:noreply, stop_running_process(state, terminal_status: "failed", stop_reason: "session_timeout")}

  def handle_info({:startup_timeout, token}, %{startup_timeout_ref: {_timer_ref, token}, status: "running"} = state),
    do: {:noreply, stop_running_process(state, terminal_status: "failed", stop_reason: "startup_timeout")}

  def handle_info({:idle_timeout, token}, %{idle_timeout_ref: {_timer_ref, token}, status: "running"} = state),
    do: {:noreply, stop_running_process(state, terminal_status: "failed", stop_reason: "idle_timeout")}

  def handle_info({:session_timeout, _token}, state), do: {:noreply, state}
  def handle_info({:startup_timeout, _token}, state), do: {:noreply, state}
  def handle_info({:idle_timeout, _token}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  @spec terminate(term(), map()) :: :ok
  def terminate(_reason, state) do
    state =
      state
      |> stop_bridge_proxy_once()
      |> release_capacity_once()

    record_lost_on_terminate(state)
    :ok
  end

  defp via(registry, session_id), do: {:via, Registry, {registry, session_id}}

  defp admit(nil, _session_id, _request), do: {:ok, nil}

  defp admit(capacity_manager, session_id, request) do
    CapacityManager.admit(capacity_manager, %{
      session_id: session_id,
      run_id: request["run_id"],
      caller: request["caller"]
    })
  end

  defp release_capacity(%{capacity_manager: nil}), do: :ok
  defp release_capacity(%{capacity_manager: capacity_manager, lease_id: lease_id}), do: CapacityManager.release(capacity_manager, lease_id)

  defp start_provider_process(context) do
    case BridgeProxy.start_from_request(context.request, Options.bridge_proxy(context.opts)) do
      {:ok, bridge_proxy} ->
        start_runner(context, bridge_proxy)

      {:error, reason} ->
        release_capacity(context)
        {:stop, reason}
    end
  end

  defp start_runner(context, bridge_proxy) do
    case context.runner.start(Request.command(context.request), context.cwd, ProviderEnvironment.env(context.request, bridge_proxy), Options.runner(context.opts)) do
      {:ok, port} ->
        os_pid = runner_os_pid(context.runner, port)
        startup_timeout_ref = schedule_startup_timeout(context.request)

        state =
          %{
            session_id: context.session_id,
            lease_id: context.lease_id,
            status: "running",
            request: context.request,
            request_fingerprint: RequestFingerprint.fingerprint(context.request),
            cwd: context.cwd,
            port: port,
            os_pid: os_pid,
            runner: context.runner,
            capacity_manager: context.capacity_manager,
            session_ledger: Keyword.get(context.opts, :session_ledger),
            events: [],
            next_event_id: 1,
            output_bytes: 0,
            output_truncated?: false,
            started_at_ms: context.now_ms,
            updated_at_ms: context.now_ms,
            output_buffer_limit: ResourceBudget.output_buffer_limit(context.request, context.opts),
            exit_status: nil,
            lost_reason: nil,
            stop_reason: nil,
            capacity_released?: false,
            bridge_proxy_stopped?: false,
            session_timeout_ref: schedule_session_timeout(context.request),
            startup_timeout_ref: startup_timeout_ref,
            idle_timeout_ref: schedule_initial_idle_timeout(context.request, startup_timeout_ref),
            bridge_proxy: bridge_proxy
          }
          |> record_ledger()

        {:ok, state}

      {:error, reason} ->
        BridgeProxy.stop(bridge_proxy)
        release_capacity(context)
        {:stop, reason}
    end
  end

  defp stop_running_process(%{status: status} = state, _opts) when status in ["exited", "failed", "cleaned", "stopped", "lost"], do: cancel_timeouts(state)

  defp stop_running_process(state, opts) do
    state = cancel_timeouts(state)
    state.runner.stop(state.port, opts)

    state
    |> stop_bridge_proxy_once()
    |> release_capacity_once()
    |> Map.put(:status, Keyword.get(opts, :terminal_status, "stopped"))
    |> Status.put_stop_reason(Keyword.get(opts, :stop_reason) || Keyword.get(opts, :reason))
    |> Map.put(:updated_at_ms, System.system_time(:millisecond))
    |> record_ledger()
  end

  defp mark_exit_status(state, status) when is_integer(status) do
    state
    |> cancel_timeouts()
    |> release_capacity_once()
    |> Map.put(:status, Status.exit_status_name(status))
    |> Map.put(:exit_status, status)
    |> Map.put(:updated_at_ms, System.system_time(:millisecond))
    |> record_ledger()
  end

  defp record_ledger(state) when is_map(state) do
    Ledger.record_session_sync(Map.get(state, :session_ledger), Payloads.summary(state))
    state
  end

  defp runner_os_pid(runner, handle) when is_atom(runner) do
    if Code.ensure_loaded?(runner) and function_exported?(runner, :os_pid, 1) do
      runner.os_pid(handle)
    end
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  defp runner_os_pid(_runner, _handle), do: nil

  defp record_lost_on_terminate(%{status: status} = state) when status in ["running"] do
    state
    |> cancel_timeouts()
    |> Map.put(:status, "lost")
    |> Map.put(:lost_reason, "session_server_terminated")
    |> Map.put(:updated_at_ms, System.system_time(:millisecond))
    |> record_ledger()
  end

  defp record_lost_on_terminate(_state), do: :ok

  defp stop_bridge_proxy_once(%{bridge_proxy_stopped?: true} = state), do: state

  defp stop_bridge_proxy_once(state) when is_map(state) do
    BridgeProxy.stop(Map.get(state, :bridge_proxy))
    Map.put(state, :bridge_proxy_stopped?, true)
  end

  defp release_capacity_once(%{capacity_released?: true} = state), do: state

  defp release_capacity_once(%{capacity_manager: nil} = state), do: Map.put(state, :capacity_released?, true)

  defp release_capacity_once(%{capacity_manager: capacity_manager, lease_id: lease_id} = state) do
    CapacityManager.release(capacity_manager, lease_id)
    Map.put(state, :capacity_released?, true)
  end

  defp schedule_session_timeout(request), do: schedule_timeout(request, "session_timeout_ms", :session_timeout)
  defp schedule_startup_timeout(request), do: schedule_timeout(request, "startup_timeout_ms", :startup_timeout)
  defp schedule_idle_timeout(request), do: schedule_timeout(request, "idle_timeout_ms", :idle_timeout)

  defp schedule_initial_idle_timeout(_request, {_timer_ref, _token}), do: nil
  defp schedule_initial_idle_timeout(request, nil), do: schedule_idle_timeout(request)

  defp schedule_timeout(request, key, tag) when is_map(request) and is_binary(key) and is_atom(tag) do
    request
    |> TimeoutPolicy.timeout_ms(key)
    |> case do
      timeout_ms when is_integer(timeout_ms) ->
        token = make_ref()
        {Process.send_after(self(), {tag, token}, timeout_ms), token}

      nil ->
        nil
    end
  end

  defp cancel_timeouts(state) do
    state
    |> cancel_session_timeout()
    |> cancel_startup_timeout()
    |> cancel_idle_timeout()
  end

  defp cancel_session_timeout(state), do: cancel_timeout(state, :session_timeout_ref)
  defp cancel_startup_timeout(state), do: cancel_timeout(state, :startup_timeout_ref)
  defp cancel_idle_timeout(state), do: cancel_timeout(state, :idle_timeout_ref)

  defp cancel_timeout(state, key) when is_map(state) and is_atom(key) do
    state
    |> Map.get(key)
    |> cancel_timeout_ref()

    Map.put(state, key, nil)
  end

  defp cancel_timeout_ref({timer_ref, _token}), do: Process.cancel_timer(timer_ref)
  defp cancel_timeout_ref(_timeout_ref), do: false

  defp note_provider_output(state) do
    state
    |> cancel_startup_timeout()
    |> reset_idle_timeout()
  end

  defp note_client_activity(%{startup_timeout_ref: {_timer_ref, _token}} = state), do: state
  defp note_client_activity(state), do: reset_idle_timeout(state)

  defp reset_idle_timeout(state) do
    state
    |> cancel_idle_timeout()
    |> Map.put(:idle_timeout_ref, schedule_idle_timeout(state.request))
  end
end
