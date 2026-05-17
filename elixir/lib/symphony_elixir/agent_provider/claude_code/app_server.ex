defmodule SymphonyElixir.AgentProvider.ClaudeCode.AppServer do
  @moduledoc """
  Claude Code provider client using its headless stream-json stdio protocol.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context, as: DynamicToolContext
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge
  alias SymphonyElixir.AgentProvider.AppServer.{Messages, PortMetadata}

  alias SymphonyElixir.AgentProvider.ClaudeCode.AppServer.{
    EventFields,
    Launcher,
    ProcessLifecycle,
    StreamProtocol,
    Usage
  }

  alias SymphonyElixir.AgentProvider.ClaudeCode.Settings
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @provider_kind Kinds.claude_code()

  @type session :: %{
          agent_provider_kind: String.t(),
          port: term(),
          metadata: map(),
          session_id: String.t(),
          thread_id: String.t(),
          workspace: Path.t(),
          worker_host: String.t() | nil,
          settings: Settings.t(),
          run_id: String.t() | nil,
          dynamic_tool_bridge: DynamicToolBridge.runtime(),
          tool_context: DynamicToolContext.t()
        }

  @spec start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Launcher.runtime_worker_host(opts)
    run_id = Keyword.get(opts, :run_id)
    settings = Keyword.fetch!(opts, :claude_code_settings)
    session_id = Ecto.UUID.generate()

    with :ok <- Launcher.validate_runtime_placement(opts),
         {:ok, expanded_workspace} <- Launcher.validate_workspace_cwd(workspace, worker_host) do
      start_session_with_bridge(expanded_workspace, settings, session_id, worker_host, run_id, opts)
    end
  end

  @spec run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(%{} = session, prompt, issue, opts \\ []) when is_binary(prompt) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    started_at_ms = monotonic_ms()

    Messages.emit(
      on_message,
      :turn_started,
      %{session_id: session.session_id, thread_id: session.thread_id, title: Messages.issue_title(issue)},
      session.metadata
    )

    ObsLogger.emit(
      :info,
      :claude_code_turn_started,
      EventFields.build(session.workspace, session.worker_host, issue, %{
        run_id: session.run_id,
        correlation_id: session.run_id,
        session_id: session.session_id,
        thread_id: session.thread_id,
        prompt_hash: :crypto.hash(:sha256, prompt) |> Base.encode16(case: :lower)
      })
    )

    with :ok <- StreamProtocol.send_turn_input(session.port, prompt),
         {:ok, response} <- StreamProtocol.await_turn_result(session, on_message, started_at_ms) do
      usage = Usage.result_usage(response)
      turn_id = Usage.result_turn_id(response)

      Messages.emit(
        on_message,
        :turn_completed,
        %{session_id: session.session_id, thread_id: session.thread_id, payload: response, usage: usage},
        session.metadata
      )

      ObsLogger.emit(
        :info,
        :claude_code_turn_completed,
        EventFields.build(session.workspace, session.worker_host, issue, %{
          run_id: session.run_id,
          correlation_id: session.run_id,
          session_id: session.session_id,
          thread_id: session.thread_id,
          turn_id: turn_id,
          usage: usage,
          duration_ms: elapsed_ms(started_at_ms)
        })
      )

      {:ok,
       %{
         result: response,
         session_id: session.session_id,
         thread_id: session.thread_id,
         turn_id: turn_id,
         usage: usage
       }}
    else
      {:error, reason} ->
        Messages.emit(
          on_message,
          :turn_ended_with_error,
          %{session_id: session.session_id, thread_id: session.thread_id, reason: reason},
          session.metadata
        )

        ObsLogger.emit(
          :warning,
          :claude_code_turn_failed,
          EventFields.build(session.workspace, session.worker_host, issue, %{
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
  def stop_session(%{port: port} = session, opts \\ []) do
    status = Keyword.get(opts, :status, :completed)
    issue = Keyword.get(opts, :issue)

    {level, event} =
      case status do
        :failed -> {:error, :claude_code_session_failed}
        _ -> {:info, :claude_code_session_completed}
      end

    ObsLogger.emit(
      level,
      event,
      EventFields.build(session.workspace, session.worker_host, issue, %{
        run_id: session.run_id,
        correlation_id: session.run_id,
        session_id: session.session_id,
        thread_id: session.thread_id
      })
    )

    _ = ProcessLifecycle.stop_port(port)
    DynamicToolBridge.stop(Map.get(session, :dynamic_tool_bridge))
  end

  defp start_session_with_bridge(expanded_workspace, settings, session_id, worker_host, run_id, opts) do
    tool_context = DynamicToolContext.from_opts(opts)

    bridge_opts =
      opts
      |> Keyword.put(:session_id, session_id)
      |> Keyword.put_new(:tool_context, tool_context)

    with {:ok, bridge_runtime} <- DynamicToolBridge.start(bridge_opts) do
      start_opts = Keyword.put(bridge_opts, :dynamic_tool_bridge_runtime, bridge_runtime)

      case Launcher.start_port(expanded_workspace, settings, session_id, start_opts) do
        {:ok, port} ->
          bridge_metadata = DynamicToolBridge.metadata(bridge_runtime)
          metadata = PortMetadata.metadata(@provider_kind, port, worker_host, run_id) |> Map.merge(bridge_metadata)

          ObsLogger.emit(
            :info,
            :claude_code_session_started,
            EventFields.build(
              expanded_workspace,
              worker_host,
              nil,
              Map.merge(
                %{
                  run_id: run_id,
                  correlation_id: run_id,
                  session_id: session_id,
                  agent_process_pid: Map.get(metadata, :agent_process_pid)
                },
                bridge_metadata
              )
            )
          )

          {:ok,
           %{
             agent_provider_kind: @provider_kind,
             port: port,
             metadata: metadata,
             session_id: session_id,
             thread_id: session_id,
             workspace: expanded_workspace,
             worker_host: worker_host,
             settings: settings,
             run_id: run_id,
             dynamic_tool_bridge: bridge_runtime,
             tool_context: tool_context
           }}

        {:error, reason} ->
          DynamicToolBridge.stop(bridge_runtime)
          {:error, reason}
      end
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
  defp elapsed_ms(started_at_ms), do: max(monotonic_ms() - started_at_ms, 0)
  defp default_on_message(_message), do: :ok
end
