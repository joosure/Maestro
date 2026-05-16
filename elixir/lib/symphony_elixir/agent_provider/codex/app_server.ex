defmodule SymphonyElixir.AgentProvider.Codex.AppServer do
  @moduledoc """
  Minimal client for the Codex app-server JSON-RPC 2.0 stream over stdio.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context, as: DynamicToolContext
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge
  alias SymphonyElixir.AgentProvider.AppServer.PortMetadata
  alias SymphonyElixir.AgentProvider.Codex.AppServer.EventFields
  alias SymphonyElixir.AgentProvider.Codex.AppServer.Launcher
  alias SymphonyElixir.AgentProvider.Codex.AppServer.Messages
  alias SymphonyElixir.AgentProvider.Codex.AppServer.ProcessLifecycle
  alias SymphonyElixir.AgentProvider.Codex.AppServer.SessionProtocol
  alias SymphonyElixir.AgentProvider.Codex.AppServer.TurnStream
  alias SymphonyElixir.AgentProvider.Codex.Settings, as: CodexSettings
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @type session :: %{
          agent_provider_kind: String.t(),
          port: term(),
          metadata: map(),
          approval_policy: String.t() | map(),
          auto_approve_requests: boolean(),
          dynamic_tool_specs: [map()],
          read_timeout_ms: pos_integer(),
          stall_timeout_ms: non_neg_integer(),
          thread_sandbox: String.t(),
          turn_timeout_ms: pos_integer(),
          turn_sandbox_policy: map(),
          run_id: String.t() | nil,
          thread_id: String.t(),
          dynamic_tool_bridge: DynamicToolBridge.runtime(),
          tool_context: DynamicToolContext.t(),
          workspace: Path.t(),
          worker_host: String.t() | nil
        }

  @spec run(Path.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(workspace, prompt, issue, opts \\ []) do
    with {:ok, session} <- start_session(workspace, opts) do
      try do
        result = run_turn(session, prompt, issue, opts)
        stop_session(session, run_session_stop_options(result, issue))
        result
      rescue
        exception ->
          stop_session(session, failed_session_stop_options(issue, inspect(exception)))
          reraise(exception, __STACKTRACE__)
      catch
        kind, reason ->
          stacktrace = __STACKTRACE__
          stop_session(session, failed_session_stop_options(issue, inspect({kind, reason})))
          :erlang.raise(kind, reason, stacktrace)
      end
    end
  end

  @spec start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Keyword.get(opts, :worker_host)
    run_id = Keyword.get(opts, :run_id)
    codex_settings = Keyword.get(opts, :codex_settings, CodexSettings.from_options(%{}))
    runtime_context = Keyword.get(opts, :provider_runtime_context, %{})

    with {:ok, expanded_workspace} <- Launcher.validate_workspace_cwd(workspace, worker_host, runtime_context),
         {:ok, session} <-
           start_session_with_bridge(expanded_workspace, worker_host, codex_settings, runtime_context, run_id, opts) do
      {:ok, session}
    else
      {:error, reason} = error ->
        ObsLogger.emit(
          :error,
          :codex_session_failed,
          EventFields.event(workspace, worker_host, nil, %{
            run_id: run_id,
            correlation_id: run_id,
            error: inspect(reason)
          })
        )

        error
    end
  end

  @spec run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(
        %{
          port: port,
          metadata: metadata,
          approval_policy: approval_policy,
          auto_approve_requests: auto_approve_requests,
          read_timeout_ms: read_timeout_ms,
          stall_timeout_ms: stall_timeout_ms,
          turn_timeout_ms: turn_timeout_ms,
          turn_sandbox_policy: turn_sandbox_policy,
          run_id: run_id,
          thread_id: thread_id,
          workspace: workspace,
          worker_host: worker_host
        },
        prompt,
        issue,
        opts \\ []
      ) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)

    case SessionProtocol.start_turn(
           port,
           thread_id,
           prompt,
           issue,
           workspace,
           approval_policy,
           turn_sandbox_policy,
           read_timeout_ms
         ) do
      {:ok, turn_id} ->
        session_id = "#{thread_id}-#{turn_id}"

        turn_context = %{
          issue: issue,
          run_id: run_id,
          session_id: session_id,
          thread_id: thread_id,
          turn_id: turn_id,
          workspace: workspace,
          worker_host: worker_host
        }

        ObsLogger.emit(
          :info,
          :codex_turn_started,
          EventFields.turn(turn_context, %{
            prompt_hash: EventFields.prompt_hash(prompt),
            correlation_id: run_id
          })
        )

        Messages.emit(
          on_message,
          :session_started,
          %{
            run_id: run_id,
            session_id: session_id,
            thread_id: thread_id,
            turn_id: turn_id
          },
          metadata
        )

        case TurnStream.await_completion(
               port,
               on_message,
               auto_approve_requests,
               turn_context,
               turn_timeout_ms,
               stall_timeout_ms
             ) do
          {:ok, result} ->
            ObsLogger.emit(
              :info,
              :codex_turn_completed,
              EventFields.turn(turn_context, %{result_summary: EventFields.stream_summary(result)})
            )

            {:ok,
             %{
               result: result,
               session_id: session_id,
               thread_id: thread_id,
               turn_id: turn_id
             }}

          {:error, reason} ->
            ObsLogger.emit(
              :warning,
              :codex_turn_failed,
              EventFields.turn(turn_context, %{error: inspect(reason), correlation_id: run_id})
            )

            Messages.emit(
              on_message,
              :turn_ended_with_error,
              %{
                run_id: run_id,
                session_id: session_id,
                reason: reason
              },
              metadata
            )

            {:error, reason}
        end

      {:error, reason} ->
        ObsLogger.emit(
          :error,
          :codex_turn_failed,
          EventFields.event(workspace, worker_host, issue, %{
            run_id: run_id,
            correlation_id: run_id,
            thread_id: thread_id,
            error: inspect(reason)
          })
        )

        Messages.emit(on_message, :startup_failed, %{run_id: run_id, reason: reason}, metadata)
        {:error, reason}
    end
  end

  @spec stop_session(session(), keyword()) :: :ok
  def stop_session(%{port: port} = session, opts \\ []) do
    status = Keyword.get(opts, :status, :completed)
    issue = Keyword.get(opts, :issue)
    extra = Keyword.get(opts, :extra, %{})

    {level, event} =
      case status do
        :failed -> {:error, :codex_session_failed}
        _ -> {:info, :codex_session_completed}
      end

    stop_context =
      EventFields.event(
        Map.get(session, :workspace),
        Map.get(session, :worker_host),
        issue,
        extra
        |> Map.put_new(:run_id, Map.get(session, :run_id))
        |> Map.put_new(:correlation_id, Map.get(session, :run_id))
        |> Map.put_new(:thread_id, Map.get(session, :thread_id))
      )

    ObsLogger.emit(
      level,
      event,
      stop_context
    )

    ProcessLifecycle.stop_port(port, stop_context)
    DynamicToolBridge.stop(Map.get(session, :dynamic_tool_bridge))
  end

  defp start_session_with_bridge(expanded_workspace, worker_host, codex_settings, runtime_context, run_id, opts) do
    tool_context = planned_tool_context(opts)

    bridge_opts =
      opts
      |> Keyword.put(:tool_context, tool_context)
      |> Keyword.put_new(:session_id, run_id || Ecto.UUID.generate())

    with {:ok, bridge_runtime} <- DynamicToolBridge.start(bridge_opts) do
      start_opts = Keyword.put(bridge_opts, :dynamic_tool_bridge_runtime, bridge_runtime)

      case Launcher.start_port(expanded_workspace, worker_host, codex_settings, runtime_context, start_opts) do
        {:ok, port} ->
          start_thread(expanded_workspace, worker_host, codex_settings, runtime_context, run_id, port, bridge_runtime, tool_context)

        {:error, reason} ->
          DynamicToolBridge.stop(bridge_runtime)
          {:error, reason}
      end
    end
  end

  defp start_thread(expanded_workspace, worker_host, codex_settings, runtime_context, run_id, port, bridge_runtime, tool_context) do
    metadata =
      PortMetadata.metadata("codex", port, worker_host)
      |> Map.merge(DynamicToolBridge.metadata(bridge_runtime))

    dynamic_tool_specs = DynamicToolContext.tool_specs(tool_context)

    with {:ok, session_policies} <- session_policies(codex_settings, runtime_context),
         {:ok, thread_id} <-
           SessionProtocol.start_session(
             port,
             expanded_workspace,
             session_policies,
             codex_settings.read_timeout_ms
           ) do
      ObsLogger.emit(
        :info,
        :codex_session_started,
        EventFields.event(
          expanded_workspace,
          worker_host,
          nil,
          Map.merge(
            %{
              run_id: run_id,
              correlation_id: run_id,
              thread_id: thread_id
            },
            DynamicToolBridge.metadata(bridge_runtime)
          )
        )
      )

      {:ok,
       %{
         agent_provider_kind: "codex",
         port: port,
         metadata: metadata,
         approval_policy: session_policies.approval_policy,
         auto_approve_requests: session_policies.approval_policy == "never",
         dynamic_tool_specs: dynamic_tool_specs,
         read_timeout_ms: codex_settings.read_timeout_ms,
         stall_timeout_ms: codex_settings.stall_timeout_ms,
         thread_sandbox: session_policies.thread_sandbox,
         turn_timeout_ms: codex_settings.turn_timeout_ms,
         turn_sandbox_policy: session_policies.turn_sandbox_policy,
         run_id: run_id,
         thread_id: thread_id,
         dynamic_tool_bridge: bridge_runtime,
         tool_context: tool_context,
         workspace: expanded_workspace,
         worker_host: worker_host
       }}
    else
      {:error, reason} ->
        ObsLogger.emit(
          :error,
          :codex_session_failed,
          EventFields.event(expanded_workspace, worker_host, nil, %{
            run_id: run_id,
            correlation_id: run_id,
            error: inspect(reason)
          })
        )

        ProcessLifecycle.stop_port(
          port,
          EventFields.event(expanded_workspace, worker_host, nil, %{
            run_id: run_id,
            correlation_id: run_id
          })
        )

        DynamicToolBridge.stop(bridge_runtime)
        {:error, reason}
    end
  end

  defp planned_tool_context(opts) when is_list(opts) do
    case Keyword.get(opts, :tool_context) do
      %{tool_specs: tool_specs} when is_list(tool_specs) -> DynamicToolContext.from_opts(opts)
      %{"tool_specs" => tool_specs} when is_list(tool_specs) -> DynamicToolContext.from_opts(opts)
      _context -> DynamicToolContext.empty()
    end
  end

  defp session_policies(%CodexSettings{} = codex_settings, runtime_context) when is_map(runtime_context) do
    case Map.get(runtime_context, :turn_sandbox_policy) || Map.get(runtime_context, "turn_sandbox_policy") do
      %{} = turn_sandbox_policy ->
        {:ok,
         %{
           approval_policy: codex_settings.approval_policy,
           thread_sandbox: codex_settings.thread_sandbox,
           turn_sandbox_policy: turn_sandbox_policy
         }}

      other ->
        {:error, {:unsafe_turn_sandbox_policy, {:missing_runtime_turn_sandbox_policy, other}}}
    end
  end

  defp run_session_stop_options({:ok, _result}, issue), do: [issue: issue]

  defp run_session_stop_options({:error, reason}, issue) do
    failed_session_stop_options(issue, inspect(reason))
  end

  defp failed_session_stop_options(issue, error) do
    [status: :failed, issue: issue, extra: %{error: error}]
  end

  defp default_on_message(_message), do: :ok
end
