defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer do
  @moduledoc """
  Minimal CodeBuddy Code ACP stdio client.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context, as: DynamicToolContext
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge
  alias SymphonyElixir.AgentProvider.AppServer.{Messages, PortMetadata}

  alias SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.{
    EventFields,
    HttpProtocol,
    Launcher,
    ProcessLifecycle,
    Protocol
  }

  alias SymphonyElixir.AgentProvider.CodeBuddyCode.{AuxiliaryHttp, Settings, Tooling}
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @provider_kind Kinds.codebuddy_code()

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
          acp_http: HttpProtocol.connection() | nil,
          provider_metadata: map(),
          dynamic_tool_bridge: DynamicToolBridge.runtime() | nil,
          tool_context: DynamicToolContext.t()
        }

  @spec start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Launcher.runtime_worker_host(opts)
    run_id = Keyword.get(opts, :run_id)
    settings = Keyword.fetch!(opts, :codebuddy_code_settings)
    runtime_session_id = Ecto.UUID.generate()

    with :ok <- Launcher.validate_runtime_placement(opts),
         {:ok, expanded_workspace} <- Launcher.validate_workspace_cwd(workspace, worker_host) do
      start_session_with_tooling(expanded_workspace, settings, runtime_session_id, worker_host, run_id, opts)
    else
      {:error, reason} = error ->
        ObsLogger.emit(
          :error,
          :codebuddy_code_session_failed,
          EventFields.build(workspace, worker_host, nil, %{run_id: run_id, correlation_id: run_id, error: inspect(reason)})
        )

        error
    end
  end

  @spec run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(%{} = session, prompt, issue, opts \\ []) when is_binary(prompt) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    started_at_ms = EventFields.monotonic_ms()

    Messages.emit(
      on_message,
      :turn_started,
      %{session_id: session.session_id, thread_id: session.thread_id, title: Messages.issue_title(issue)},
      session.metadata
    )

    ObsLogger.emit(
      :info,
      :codebuddy_code_turn_started,
      EventFields.build(session.workspace, session.worker_host, issue, %{
        run_id: session.run_id,
        correlation_id: session.run_id,
        session_id: session.session_id,
        thread_id: session.thread_id,
        prompt_hash: EventFields.prompt_hash(prompt)
      })
    )

    case prompt_protocol(session, prompt, on_message, issue) do
      {:ok, response} ->
        turn_id = Map.get(response, "userMessageId") || Map.get(response, "id")

        Messages.emit(
          on_message,
          :turn_completed,
          %{session_id: session.session_id, thread_id: session.thread_id, turn_id: turn_id, payload: response},
          session.metadata
        )

        ObsLogger.emit(
          :info,
          :codebuddy_code_turn_completed,
          EventFields.build(session.workspace, session.worker_host, issue, %{
            run_id: session.run_id,
            correlation_id: session.run_id,
            session_id: session.session_id,
            thread_id: session.thread_id,
            turn_id: turn_id,
            stop_reason: Map.get(response, "stopReason"),
            duration_ms: EventFields.elapsed_ms(started_at_ms)
          })
        )

        {:ok,
         %{
           status: :completed,
           result: response,
           session_id: session.session_id,
           thread_id: session.thread_id,
           turn_id: turn_id
         }
         |> Map.merge(turn_metadata(session, response, opts))}

      {:error, reason} ->
        Messages.emit(
          on_message,
          if(input_required?(reason), do: :turn_input_required, else: :turn_ended_with_error),
          %{session_id: session.session_id, thread_id: session.thread_id, reason: reason},
          session.metadata
        )

        ObsLogger.emit(
          :warning,
          :codebuddy_code_turn_failed,
          EventFields.build(session.workspace, session.worker_host, issue, %{
            run_id: session.run_id,
            correlation_id: session.run_id,
            session_id: session.session_id,
            thread_id: session.thread_id,
            error: inspect(reason),
            duration_ms: EventFields.elapsed_ms(started_at_ms)
          })
        )

        {:error, reason}
    end
  end

  @spec stop_session(session(), keyword()) :: :ok | {:error, term()}
  def stop_session(%{port: port} = session, opts \\ []) do
    status = Keyword.get(opts, :status, :completed)
    issue = Keyword.get(opts, :issue)

    {level, event} =
      case status do
        :failed -> {:error, :codebuddy_code_session_failed}
        _status -> {:info, :codebuddy_code_session_completed}
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

    _ = cleanup_transport(session)
    _ = ProcessLifecycle.stop_port(port)
    DynamicToolBridge.stop(Map.get(session, :dynamic_tool_bridge))
  end

  @spec start_session_with_tooling(Path.t(), Settings.t(), String.t(), String.t() | nil, String.t() | nil, keyword()) ::
          {:ok, session()} | {:error, term()}
  defp start_session_with_tooling(expanded_workspace, settings, runtime_session_id, worker_host, run_id, opts) do
    tool_context = Tooling.tool_context(settings, opts)

    bridge_opts =
      opts
      |> Keyword.put(:agent_provider_kind, @provider_kind)
      |> Keyword.put(:session_id, runtime_session_id)
      |> Keyword.put(:tool_context, tool_context)

    case DynamicToolBridge.start(bridge_opts) do
      {:ok, bridge_runtime} ->
        case start_session_with_started_bridge(expanded_workspace, settings, bridge_runtime, bridge_opts, tool_context, worker_host, run_id) do
          {:error, reason} = error ->
            emit_session_failed(expanded_workspace, worker_host, run_id, reason)
            error

          result ->
            result
        end

      {:error, reason} = error ->
        emit_session_failed(expanded_workspace, worker_host, run_id, reason)
        error
    end
  end

  defp emit_session_failed(workspace, worker_host, run_id, reason) do
    ObsLogger.emit(
      :error,
      :codebuddy_code_session_failed,
      EventFields.build(workspace, worker_host, nil, %{run_id: run_id, correlation_id: run_id, error: inspect(reason)})
    )
  end

  @spec start_session_with_started_bridge(
          Path.t(),
          Settings.t(),
          DynamicToolBridge.runtime(),
          keyword(),
          DynamicToolContext.t(),
          String.t() | nil,
          String.t() | nil
        ) :: {:ok, session()} | {:error, term()}
  defp start_session_with_started_bridge(expanded_workspace, settings, bridge_runtime, bridge_opts, tool_context, worker_host, run_id) do
    with {:ok, bridge_env} <- DynamicToolBridge.runtime_env(dynamic_tool_bridge_runtime: bridge_runtime),
         {:ok, tooling_runtime} <- Tooling.write_runtime_mcp_config(expanded_workspace, settings, bridge_opts, bridge_env) do
      start_opts =
        bridge_opts
        |> Keyword.put(:dynamic_tool_bridge_runtime, bridge_runtime)
        |> Keyword.put(:codebuddy_code_tooling_runtime, tooling_runtime)

      case Launcher.start_port(expanded_workspace, settings, start_opts) do
        {:ok, port} ->
          start_started_port(expanded_workspace, settings, port, bridge_runtime, tooling_runtime, tool_context, worker_host, run_id)

        {:error, reason} ->
          DynamicToolBridge.stop(bridge_runtime)
          {:error, reason}
      end
    else
      {:error, reason} ->
        DynamicToolBridge.stop(bridge_runtime)
        {:error, reason}
    end
  end

  @spec start_started_port(
          Path.t(),
          Settings.t(),
          term(),
          DynamicToolBridge.runtime(),
          map() | nil,
          DynamicToolContext.t(),
          String.t() | nil,
          String.t() | nil
        ) :: {:ok, session()} | {:error, term()}
  defp start_started_port(expanded_workspace, settings, port, bridge_runtime, tooling_runtime, tool_context, worker_host, run_id) do
    with {:ok, started} <- initialize_transport(expanded_workspace, settings, port),
         initialize <- Map.fetch!(started, :initialize),
         session_payload <- Map.fetch!(started, :session_payload),
         :ok <- validate_configured_model(settings, session_payload) do
      session_id = Map.fetch!(session_payload, "sessionId")
      bridge_metadata = DynamicToolBridge.metadata(bridge_runtime)

      metadata =
        PortMetadata.metadata(@provider_kind, port, worker_host, run_id)
        |> Map.merge(transport_metadata(started))
        |> Map.merge(bridge_metadata)

      ObsLogger.emit(
        :info,
        :codebuddy_code_session_started,
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
         acp_http: Map.get(started, :acp_http),
         dynamic_tool_bridge: bridge_runtime,
         tool_context: tool_context,
         provider_metadata: %{
           "initialize" => bounded_initialize_metadata(initialize),
           "session" => bounded_session_metadata(session_payload),
           "dynamic_tools" => Tooling.metadata(tooling_runtime)
         }
       }}
    else
      {:error, reason} ->
        ProcessLifecycle.stop_port(port)
        DynamicToolBridge.stop(bridge_runtime)
        {:error, reason}
    end
  end

  defp initialize_transport(expanded_workspace, %Settings{transport: "acp_stdio"} = settings, port) do
    with {:ok, initialize} <- Protocol.initialize(port, settings),
         {:ok, session_payload} <- Protocol.new_session(port, expanded_workspace, settings) do
      {:ok, %{initialize: initialize, session_payload: session_payload}}
    end
  end

  defp initialize_transport(expanded_workspace, %Settings{transport: "acp_http"} = settings, port) do
    with {:ok, base_url} <- Launcher.await_http_base_url(port, settings),
         {:ok, acp_http} <- HttpProtocol.connect(base_url, settings),
         {:ok, initialize} <- HttpProtocol.initialize(acp_http, settings),
         {:ok, session_payload} <- HttpProtocol.new_session(acp_http, expanded_workspace, settings) do
      {:ok, %{initialize: initialize, session_payload: session_payload, acp_http: acp_http}}
    end
  end

  defp initialize_transport(_expanded_workspace, %Settings{transport: transport}, _port), do: {:error, {:unsupported_transport, transport}}

  defp prompt_protocol(%{settings: %Settings{transport: "acp_http"}} = session, prompt, on_message, issue) do
    HttpProtocol.prompt(session, prompt, on_message, issue)
  end

  defp prompt_protocol(session, prompt, on_message, issue), do: Protocol.prompt(session, prompt, on_message, issue)

  defp redacted_result_meta(%{settings: %Settings{transport: "acp_http"}}, response), do: HttpProtocol.redacted_meta(response)
  defp redacted_result_meta(_session, response), do: Protocol.redacted_meta(response)

  defp turn_metadata(session, response, opts) do
    %{"provider_result" => redacted_result_meta(session, response)}
    |> maybe_put_auxiliary_http_metadata(session, opts)
  end

  defp maybe_put_auxiliary_http_metadata(metadata, %{settings: %Settings{} = settings, acp_http: %{base_url: base_url}}, opts)
       when is_binary(base_url) do
    if Settings.http_enabled?(settings) do
      Map.put(metadata, "auxiliary_http", AuxiliaryHttp.collect(base_url, settings, opts))
    else
      metadata
    end
  end

  defp maybe_put_auxiliary_http_metadata(metadata, _session, _opts), do: metadata

  defp cleanup_transport(%{settings: %Settings{transport: "acp_http"}, acp_http: acp_http}) do
    HttpProtocol.cleanup(acp_http)
  end

  defp cleanup_transport(_session), do: :ok

  defp transport_metadata(%{acp_http: %{base_url: base_url}}), do: %{acp_http_base_url: base_url}
  defp transport_metadata(_started), do: %{}

  defp input_required?({:turn_input_required, _payload}), do: true
  defp input_required?({:client_request_unsupported, _payload}), do: true
  defp input_required?(_reason), do: false

  defp bounded_initialize_metadata(%{} = payload) do
    %{
      "protocolVersion" => Map.get(payload, "protocolVersion"),
      "agentCapabilities" => Map.get(payload, "agentCapabilities", %{}),
      "authMethodIds" => auth_method_ids(Map.get(payload, "authMethods", []))
    }
  end

  defp bounded_session_metadata(%{} = payload) do
    %{
      "currentModelId" => get_in(payload, ["models", "currentModelId"]),
      "availableModelIds" =>
        payload
        |> get_in(["models", "availableModels"])
        |> model_ids(),
      "currentModeId" => get_in(payload, ["modes", "currentModeId"]),
      "availableModeIds" =>
        payload
        |> get_in(["modes", "availableModes"])
        |> mode_ids()
    }
  end

  defp validate_configured_model(%Settings{model: nil}, _session_payload), do: :ok

  defp validate_configured_model(%Settings{model: configured_model}, %{} = session_payload) do
    configured_model = normalize_model_id(configured_model)
    current_model = session_payload |> get_in(["models", "currentModelId"]) |> normalize_model_id()
    available_models = session_payload |> get_in(["models", "availableModels"]) |> model_ids()

    cond do
      is_nil(configured_model) ->
        :ok

      configured_model in available_models ->
        :ok

      available_models == [] and current_model == configured_model ->
        :ok

      true ->
        {:error,
         {:codebuddy_model_mismatch,
          %{
            configured_model: configured_model,
            current_model: current_model,
            available_models: available_models
          }}}
    end
  end

  defp model_ids(models) when is_list(models) do
    models
    |> Enum.flat_map(fn
      model when is_binary(model) ->
        [model]

      %{"id" => id} when is_binary(id) ->
        [id]

      %{"modelId" => id} when is_binary(id) ->
        [id]

      %{"name" => id} when is_binary(id) ->
        [id]

      _model ->
        []
    end)
    |> Enum.map(&normalize_model_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp model_ids(_models), do: []

  defp normalize_model_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      model -> model
    end
  end

  defp normalize_model_id(_value), do: nil

  defp auth_method_ids(methods) when is_list(methods) do
    Enum.flat_map(methods, fn
      %{"id" => id} when is_binary(id) -> [id]
      _method -> []
    end)
  end

  defp auth_method_ids(_methods), do: []

  defp mode_ids(modes) when is_list(modes) do
    Enum.flat_map(modes, fn
      %{"id" => id} when is_binary(id) -> [id]
      _mode -> []
    end)
  end

  defp mode_ids(_modes), do: []
  defp default_on_message(_message), do: :ok
end
