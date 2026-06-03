defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer do
  @moduledoc """
  OpenCode provider client using `opencode serve` over HTTP and SSE.
  """

  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge
  alias SymphonyElixir.AgentProvider.AppServer.{Messages, PortMetadata}
  alias SymphonyElixir.AgentProvider.Kinds

  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.{
    Context,
    Diagnostics,
    EventFields,
    EventStream,
    HttpRequests,
    Launcher,
    ProcessLifecycle,
    Usage
  }

  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.Transport.SyncMessage
  alias SymphonyElixir.AgentProvider.OpenCode.{Settings, Tooling}
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @provider_kind Kinds.opencode()
  @poll_interval_ms 250

  @type session :: %{
          agent_provider_kind: String.t(),
          port: port(),
          request: Req.Request.t(),
          base_url: String.t(),
          session_id: String.t(),
          thread_id: String.t(),
          metadata: map(),
          workspace: Path.t(),
          worker_host: String.t() | nil,
          settings: Settings.t(),
          run_id: String.t() | nil,
          dynamic_tool_bridge: DynamicToolBridge.runtime()
        }

  @spec start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Launcher.runtime_worker_host(opts)
    run_id = Keyword.get(opts, :run_id)
    settings = Keyword.fetch!(opts, :open_code_settings)

    with :ok <- Launcher.validate_runtime_placement(opts),
         {:ok, expanded_workspace} <- Launcher.validate_workspace_cwd(workspace),
         {:ok, bridge_runtime} <- DynamicToolBridge.start(opts) do
      start_opts = Keyword.put(opts, :dynamic_tool_bridge_runtime, bridge_runtime)

      case Tooling.prepare_workspace(expanded_workspace, start_opts) do
        :ok ->
          start_port(expanded_workspace, settings, start_opts, bridge_runtime, worker_host, run_id)

        {:error, reason} ->
          DynamicToolBridge.stop(bridge_runtime)
          {:error, reason}
      end
    end
  end

  defp start_port(expanded_workspace, settings, start_opts, bridge_runtime, worker_host, run_id) do
    case Launcher.start_port(expanded_workspace, settings, start_opts) do
      {:ok, port} ->
        bridge_metadata = DynamicToolBridge.metadata(bridge_runtime)
        metadata = PortMetadata.metadata(@provider_kind, port, worker_host, run_id) |> Map.merge(bridge_metadata)
        start_started_port(expanded_workspace, settings, port, metadata, worker_host, run_id, bridge_runtime)

      {:error, reason} ->
        DynamicToolBridge.stop(bridge_runtime)
        {:error, reason}
    end
  end

  defp start_started_port(expanded_workspace, settings, port, metadata, worker_host, run_id, bridge_runtime) do
    startup_context = Context.startup(expanded_workspace, settings, metadata, run_id)

    with {:ok, base_url} <- Launcher.await_server_url(port, startup_context),
         request_context <- Map.put(startup_context, :base_url, base_url),
         request <- HttpRequests.build_request(base_url, settings.read_timeout_ms),
         :ok <- HttpRequests.await_health(request, request_context),
         {:ok, session_id} <- HttpRequests.create_session(request, expanded_workspace, request_context) do
      ObsLogger.emit(
        :info,
        :opencode_session_started,
        EventFields.event(expanded_workspace, worker_host, nil, %{
          run_id: run_id,
          correlation_id: run_id,
          session_id: session_id,
          thread_id: session_id,
          agent_process_pid: Map.get(metadata, :agent_process_pid),
          base_url: base_url
        })
      )

      {:ok,
       %{
         agent_provider_kind: @provider_kind,
         port: port,
         request: request,
         base_url: base_url,
         session_id: session_id,
         thread_id: session_id,
         metadata: metadata,
         workspace: expanded_workspace,
         worker_host: worker_host,
         settings: settings,
         run_id: run_id,
         dynamic_tool_bridge: bridge_runtime
       }}
    else
      {:error, reason} ->
        ProcessLifecycle.stop_port(port)
        DynamicToolBridge.stop(bridge_runtime)
        {:error, reason}
    end
  end

  @spec run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(%{} = session, prompt, issue, opts \\ []) when is_binary(prompt) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    turn_ref = make_ref()
    owner = self()
    message_id = turn_message_id()

    Messages.emit(
      on_message,
      :turn_started,
      %{session_id: session.session_id, thread_id: session.thread_id, title: Messages.issue_title(issue)},
      session.metadata
    )

    ObsLogger.emit(
      :info,
      :opencode_turn_started,
      EventFields.event(session.workspace, session.worker_host, issue, %{
        run_id: session.run_id,
        correlation_id: session.run_id,
        session_id: session.session_id,
        thread_id: session.thread_id,
        message_id: message_id,
        prompt_hash: :crypto.hash(:sha256, prompt) |> Base.encode16(case: :lower)
      })
    )

    listener_task =
      Task.Supervisor.async_nolink(SymphonyElixir.TaskSupervisor, fn ->
        EventStream.stream_session_events(session, turn_ref, owner, on_message)
      end)

    prompt_task =
      Task.Supervisor.async_nolink(SymphonyElixir.TaskSupervisor, fn ->
        SyncMessage.run(session, prompt, message_id)
      end)

    started_at_ms = monotonic_ms()

    result =
      await_turn_result(
        session,
        turn_ref,
        prompt_task,
        listener_task,
        started_at_ms,
        started_at_ms,
        session.settings.turn_timeout_ms,
        session.settings.stall_timeout_ms
      )

    stop_async_task(listener_task)
    stop_async_task(prompt_task)

    case result do
      {:ok, %{} = response} ->
        usage = Usage.message_response_token_usage(response) || %{}

        Messages.emit(
          on_message,
          :turn_completed,
          %{session_id: session.session_id, thread_id: session.thread_id, payload: response, usage: usage},
          session.metadata
        )

        ObsLogger.emit(
          :info,
          :opencode_turn_completed,
          EventFields.event(session.workspace, session.worker_host, issue, %{
            run_id: session.run_id,
            correlation_id: session.run_id,
            session_id: session.session_id,
            thread_id: session.thread_id,
            turn_id: Usage.message_turn_id(response),
            usage: usage,
            duration_ms: elapsed_ms(started_at_ms)
          })
        )

        {:ok,
         %{
           result: response,
           session_id: session.session_id,
           thread_id: session.thread_id,
           turn_id: Usage.message_turn_id(response),
           usage: usage
         }}

      {:error, reason} ->
        Messages.emit(
          on_message,
          :turn_ended_with_error,
          %{session_id: session.session_id, thread_id: session.thread_id, reason: reason},
          session.metadata
        )

        ObsLogger.emit(
          :warning,
          :opencode_turn_failed,
          EventFields.event(session.workspace, session.worker_host, issue, %{
            run_id: session.run_id,
            correlation_id: session.run_id,
            session_id: session.session_id,
            thread_id: session.thread_id,
            error: inspect(reason),
            duration_ms: elapsed_ms(started_at_ms)
          })
        )

        {:error, reason}
    end
  end

  @spec stop_session(session(), keyword()) :: :ok
  def stop_session(%{port: port} = session, opts \\ []) when is_port(port) do
    status = Keyword.get(opts, :status, :completed)
    issue = Keyword.get(opts, :issue)

    {level, event} =
      case status do
        :failed -> {:error, :opencode_session_failed}
        _ -> {:info, :opencode_session_completed}
      end

    ObsLogger.emit(
      level,
      event,
      EventFields.event(session.workspace, session.worker_host, issue, %{
        run_id: session.run_id,
        correlation_id: session.run_id,
        session_id: session.session_id,
        thread_id: session.thread_id,
        base_url: session.base_url
      })
    )

    ProcessLifecycle.stop_port(port)
    DynamicToolBridge.stop(Map.get(session, :dynamic_tool_bridge))
  end

  defp await_turn_result(
         session,
         turn_ref,
         prompt_task,
         listener_task,
         started_at_ms,
         last_activity_ms,
         turn_timeout_ms,
         stall_timeout_ms
       ) do
    prompt_ref = prompt_task.ref
    listener_ref = listener_task.ref

    receive do
      {^turn_ref, :activity, activity_ms} ->
        await_turn_result(
          session,
          turn_ref,
          prompt_task,
          listener_task,
          started_at_ms,
          max(last_activity_ms, activity_ms),
          turn_timeout_ms,
          stall_timeout_ms
        )

      {^turn_ref, :turn_failed, reason} ->
        HttpRequests.abort_session(session)
        stop_async_task(prompt_task)
        {:error, reason}

      {^turn_ref, :stream_error, reason} ->
        HttpRequests.abort_session(session)
        stop_async_task(prompt_task)
        {:error, reason}

      {^prompt_ref, {:ok, %{} = response}} ->
        flush_task_down(prompt_ref)
        {:ok, response}

      {^prompt_ref, {:error, reason}} ->
        flush_task_down(prompt_ref)
        stop_async_task(listener_task)
        {:error, reason}

      {^listener_ref, _result} ->
        flush_task_down(listener_ref)

        await_turn_result(
          session,
          turn_ref,
          prompt_task,
          listener_task,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
        )

      {:DOWN, ^prompt_ref, :process, _pid, :normal} ->
        case take_task_result(prompt_ref) do
          {:ok, {:ok, %{} = response}} ->
            {:ok, response}

          {:ok, {:error, reason}} ->
            stop_async_task(listener_task)
            {:error, reason}

          :missing ->
            await_turn_result(
              session,
              turn_ref,
              prompt_task,
              listener_task,
              started_at_ms,
              last_activity_ms,
              turn_timeout_ms,
              stall_timeout_ms
            )
        end

      {:DOWN, ^prompt_ref, :process, _pid, reason} ->
        stop_async_task(listener_task)

        {:error,
         {:turn_message_transport_error,
          Map.merge(Context.session(session), %{
            cause: Diagnostics.preview_value(reason),
            message: "OpenCode message task exited unexpectedly while waiting for the turn response"
          })}}

      {:DOWN, ^listener_ref, :process, _pid, _reason} ->
        await_turn_result(
          session,
          turn_ref,
          prompt_task,
          listener_task,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
        )

      {port, {:data, {:eol, chunk}}} when port == session.port ->
        Diagnostics.log_port_output("server", IO.chardata_to_string(chunk))

        await_turn_result(
          session,
          turn_ref,
          prompt_task,
          listener_task,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
        )

      {port, {:data, {:noeol, chunk}}} when port == session.port ->
        Diagnostics.log_port_output("server", IO.chardata_to_string(chunk))

        await_turn_result(
          session,
          turn_ref,
          prompt_task,
          listener_task,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
        )

      {port, {:exit_status, status}} when port == session.port ->
        {:error, {:port_exit, status}}
    after
      @poll_interval_ms ->
        now_ms = monotonic_ms()

        cond do
          turn_timeout_ms > 0 and now_ms - started_at_ms > turn_timeout_ms ->
            HttpRequests.abort_session(session)
            stop_async_task(prompt_task)
            {:error, :turn_timeout}

          stall_timeout_ms > 0 and now_ms - last_activity_ms > stall_timeout_ms ->
            HttpRequests.abort_session(session)
            stop_async_task(prompt_task)
            {:error, :stall_timeout}

          true ->
            await_turn_result(
              session,
              turn_ref,
              prompt_task,
              listener_task,
              started_at_ms,
              last_activity_ms,
              turn_timeout_ms,
              stall_timeout_ms
            )
        end
    end
  end

  defp stop_async_task(%Task{} = task) do
    Task.shutdown(task, :brutal_kill)
    :ok
  rescue
    _error -> :ok
  end

  defp flush_task_down(ref) do
    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    after
      0 -> :ok
    end
  end

  defp take_task_result(ref) do
    receive do
      {^ref, result} -> {:ok, result}
    after
      0 -> :missing
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
  defp elapsed_ms(started_at_ms), do: max(monotonic_ms() - started_at_ms, 0)
  defp default_on_message(_message), do: :ok
  defp turn_message_id, do: "msg_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
