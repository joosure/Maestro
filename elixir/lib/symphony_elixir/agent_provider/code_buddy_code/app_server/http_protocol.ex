defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.HttpProtocol do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.AppServer.{Messages, PortMetadata}
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.EventFields
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.Settings
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.Observability.Redaction

  @provider_kind Kinds.codebuddy_code()
  @initialize_id 0
  @session_new_id 1
  @prompt_id 2
  @poll_interval_ms 250

  @type connection :: %{
          request: Req.Request.t(),
          base_url: String.t(),
          endpoint_path: String.t()
        }

  @spec connect(String.t(), Settings.t()) :: {:ok, connection()} | {:error, term()}
  def connect(base_url, %Settings{} = settings) when is_binary(base_url) do
    endpoint_path = Settings.acp_endpoint_path(settings)
    request = build_request(base_url, settings, %{"accept" => "application/json"})

    with {:ok, connection_id, session_token} <- await_acp_connect(request, endpoint_path, settings) do
      {:ok,
       %{
         request: build_connected_request(base_url, settings, connection_id, session_token),
         base_url: base_url,
         endpoint_path: endpoint_path
       }}
    end
  end

  @spec initialize(connection(), Settings.t()) :: {:ok, map()} | {:error, term()}
  def initialize(%{} = connection, %Settings{} = settings) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => @initialize_id,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => 1,
        "clientCapabilities" => %{},
        "clientInfo" => %{
          "name" => "symphony-orchestrator",
          "title" => "Symphony Orchestrator",
          "version" => "0.1.0"
        }
      }
    }

    post_rpc_result(connection, payload, @initialize_id, handshake_timeout_ms(settings))
  end

  @spec new_session(connection(), Path.t(), Settings.t()) :: {:ok, map()} | {:error, term()}
  def new_session(%{} = connection, workspace, %Settings{} = settings) when is_binary(workspace) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => @session_new_id,
      "method" => "session/new",
      "params" => %{
        "cwd" => workspace,
        "mcpServers" => []
      }
    }

    case post_rpc_result(connection, payload, @session_new_id, handshake_timeout_ms(settings)) do
      {:ok, %{"sessionId" => session_id} = response} when is_binary(session_id) -> {:ok, response}
      {:ok, response} -> {:error, {:invalid_session_new_response, response}}
      {:error, _reason} = error -> error
    end
  end

  @spec prompt(map(), String.t(), (map() -> term()), map()) :: {:ok, map()} | {:error, term()}
  def prompt(%{} = session, prompt, on_message, issue)
      when is_binary(prompt) and is_function(on_message, 1) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => @prompt_id,
      "method" => "session/prompt",
      "params" => %{
        "sessionId" => session.session_id,
        "prompt" => [
          %{
            "type" => "text",
            "text" => prompt
          }
        ]
      }
    }

    owner = self()
    turn_ref = make_ref()
    started_at_ms = EventFields.monotonic_ms()
    turn_context = turn_context(session, issue)
    relay_on_message = fn message -> send(owner, {turn_ref, :message, message}) end

    task =
      Task.Supervisor.async_nolink(SymphonyElixir.TaskSupervisor, fn ->
        post_prompt_stream(session, payload, relay_on_message, turn_context, turn_ref, owner)
      end)

    await_prompt_task(session, task, turn_ref, on_message, started_at_ms, nil)
  end

  @spec cleanup(map()) :: :ok | {:error, term()}
  def cleanup(%{request: request, endpoint_path: endpoint_path}) do
    case Req.delete(request, url: endpoint_path, headers: %{"accept" => "application/json"}) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, http_error("DELETE", endpoint_path, status, body)}
      {:error, reason} -> {:error, transport_error("DELETE", endpoint_path, reason)}
    end
  end

  def cleanup(_connection), do: :ok

  @spec redacted_meta(map()) :: map()
  def redacted_meta(%{} = payload) do
    payload
    |> Map.take(["stopReason", "_meta"])
    |> redact_meta()
  end

  def redacted_meta(_payload), do: %{}

  defp build_request(base_url, settings, headers) do
    Req.new(
      base_url: base_url,
      retry: false,
      receive_timeout: settings.read_timeout_ms,
      connect_options: [timeout: settings.read_timeout_ms],
      headers: Map.merge(%{"x-codebuddy-request" => "1"}, headers)
    )
  end

  defp build_connected_request(base_url, settings, connection_id, session_token) do
    build_request(base_url, settings, %{
      "accept" => "application/json",
      "acp-connection-id" => connection_id,
      "authorization" => "Bearer " <> session_token
    })
  end

  defp await_acp_connect(request, endpoint_path, settings) do
    deadline = EventFields.monotonic_ms() + settings.read_timeout_ms
    await_acp_connect_until(request, endpoint_path, deadline)
  end

  defp await_acp_connect_until(request, endpoint_path, deadline) do
    case connect_acp(request, endpoint_path) do
      {:ok, _connection_id, _session_token} = result ->
        result

      {:error, reason} ->
        sleep_or_timeout(
          deadline,
          fn -> {:error, {:codebuddy_acp_http_connect_timeout, %{reason: preview(reason)}}} end,
          fn -> await_acp_connect_until(request, endpoint_path, deadline) end
        )
    end
  end

  defp connect_acp(request, endpoint_path) do
    path = endpoint_path <> "/connect"

    case Req.post(request, url: path, json: %{}) do
      {:ok, %{status: status, body: %{"connectionId" => connection_id, "sessionToken" => session_token}}}
      when status in 200..299 and is_binary(connection_id) and is_binary(session_token) ->
        {:ok, connection_id, session_token}

      {:ok, %{status: status, body: body}} ->
        {:error, http_error("POST", path, status, body)}

      {:error, reason} ->
        {:error, transport_error("POST", path, reason)}
    end
  end

  defp post_rpc_result(connection, payload, request_id, timeout_ms) do
    task =
      Task.Supervisor.async_nolink(SymphonyElixir.TaskSupervisor, fn ->
        post_rpc_result_stream(connection, payload, request_id, timeout_ms)
      end)

    await_result_task(task, timeout_ms)
  end

  defp post_rpc_result_stream(connection, payload, request_id, timeout_ms) do
    case post_stream(connection, payload) do
      {:ok, response} ->
        collect_stream_response(response, %{
          connection: connection,
          request_id: request_id,
          mode: :result,
          timeout_ms: timeout_ms,
          buffer: ""
        })

      {:error, _reason} = error ->
        error
    end
  end

  defp await_result_task(task, timeout_ms) do
    task_ref = task.ref

    receive do
      {^task_ref, result} ->
        flush_task_down(task_ref)
        result

      {:DOWN, ^task_ref, :process, _pid, reason} ->
        {:error, {:codebuddy_acp_http_transport_error, %{reason: preview(reason)}}}
    after
      timeout_ms ->
        stop_async_task(task)
        {:error, :response_timeout}
    end
  end

  defp post_prompt_stream(session, payload, on_message, turn_context, turn_ref, owner) do
    case post_stream(session.acp_http, payload) do
      {:ok, response} ->
        collect_stream_response(response, %{
          connection: session.acp_http,
          request_id: @prompt_id,
          mode: :prompt,
          session: session,
          on_message: on_message,
          turn_context: turn_context,
          turn_ref: turn_ref,
          owner: owner,
          timeout_ms: @poll_interval_ms,
          buffer: ""
        })

      {:error, _reason} = error ->
        error
    end
  end

  defp post_stream(%{request: request, endpoint_path: endpoint_path}, payload) do
    case Req.post(request,
           url: endpoint_path,
           json: payload,
           decode_body: false,
           into: :self,
           headers: %{"accept" => "application/json, text/event-stream"}
         ) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, http_error("POST", endpoint_path, status, body)}

      {:error, reason} ->
        {:error, transport_error("POST", endpoint_path, reason)}
    end
  rescue
    error -> {:error, transport_error("POST", endpoint_path, error)}
  end

  defp collect_stream_response(response, state) do
    receive do
      message ->
        case Req.parse_message(response, message) do
          {:ok, chunks} ->
            handle_stream_chunks(chunks, response, state)

          :unknown ->
            collect_stream_response(response, state)

          {:error, reason} ->
            {:error, {:codebuddy_acp_http_transport_error, %{reason: preview(reason)}}}
        end
    after
      Map.fetch!(state, :timeout_ms) ->
        if Map.get(state, :mode) == :prompt do
          collect_stream_response(response, state)
        else
          {:error, :response_timeout}
        end
    end
  end

  defp handle_stream_chunks(chunks, response, state) do
    Enum.reduce_while(chunks, {:cont, state}, fn
      {:data, data}, {:cont, state_acc} ->
        {next_buffer, events} = parse_sse_events(Map.fetch!(state_acc, :buffer), data)
        next_state = Map.put(state_acc, :buffer, next_buffer)

        case handle_sse_events(events, next_state) do
          {:cont, state_after_events} -> {:cont, {:cont, state_after_events}}
          {:halt, result} -> {:halt, {:halt, result}}
        end

      :done, {:cont, state_acc} ->
        {:halt, {:halt, stream_done_result(state_acc)}}

      _chunk, {:cont, state_acc} ->
        {:cont, {:cont, state_acc}}
    end)
    |> case do
      {:cont, next_state} -> collect_stream_response(response, next_state)
      {:halt, result} -> result
    end
  end

  defp handle_sse_events(events, state) do
    Enum.reduce_while(events, {:cont, state}, fn event, {:cont, state_acc} ->
      case handle_json_rpc_event(event, state_acc) do
        {:cont, next_state} -> {:cont, {:cont, next_state}}
        {:halt, result} -> {:halt, {:halt, result}}
      end
    end)
  end

  defp handle_json_rpc_event(%{"id" => request_id, "error" => error}, %{request_id: request_id}) do
    {:halt, {:error, {:response_error, error}}}
  end

  defp handle_json_rpc_event(%{"id" => request_id, "result" => %{} = result}, %{request_id: request_id, mode: :prompt}) do
    {:halt, terminal_result(result)}
  end

  defp handle_json_rpc_event(%{"id" => request_id, "result" => result}, %{request_id: request_id, mode: :result}) do
    {:halt, {:ok, result}}
  end

  defp handle_json_rpc_event(%{"id" => request_id} = payload, %{request_id: request_id}) do
    {:halt, {:error, {:response_error, payload}}}
  end

  defp handle_json_rpc_event(%{"id" => _id, "method" => method} = payload, %{mode: :prompt} = state) when is_binary(method) do
    handle_client_request(state, payload)
  end

  defp handle_json_rpc_event(%{"method" => "session/update"} = payload, %{mode: :prompt} = state) do
    emit_session_update(state, payload, Jason.encode!(payload))
    send_activity(state)
    {:cont, state}
  end

  defp handle_json_rpc_event(%{"method" => method} = payload, %{mode: :prompt} = state) when is_binary(method) do
    Messages.emit(
      state.on_message,
      :notification,
      %{payload: payload, raw: Jason.encode!(payload)},
      PortMetadata.message(@provider_kind, state.session.port, payload, state.turn_context)
    )

    send_activity(state)
    {:cont, state}
  end

  defp handle_json_rpc_event(_payload, state), do: {:cont, state}

  defp stream_done_result(%{mode: :result}), do: {:error, :response_timeout}
  defp stream_done_result(%{mode: :prompt}), do: {:error, :response_timeout}

  defp await_prompt_task(session, task, turn_ref, on_message, started_at_ms, last_activity_ms) do
    task_ref = task.ref

    case timeout_reason(started_at_ms, last_activity_ms, session.settings) do
      nil ->
        receive do
          {^turn_ref, :activity, activity_ms} ->
            await_prompt_task(session, task, turn_ref, on_message, started_at_ms, activity_ms)

          {^turn_ref, :message, message} ->
            on_message.(message)
            await_prompt_task(session, task, turn_ref, on_message, started_at_ms, last_activity_ms)

          {^task_ref, result} ->
            flush_task_down(task_ref)
            maybe_cancel_prompt_error(session, result)
            result

          {:DOWN, ^task_ref, :process, _pid, reason} ->
            {:error, {:codebuddy_acp_http_transport_error, %{reason: preview(reason)}}}
        after
          receive_timeout_ms(started_at_ms, last_activity_ms, session.settings) ->
            timeout = timeout_reason(started_at_ms, last_activity_ms, session.settings) || :turn_timeout
            _ = cancel_session(session)
            stop_async_task(task)
            {:error, timeout}
        end

      reason ->
        _ = cancel_session(session)
        stop_async_task(task)
        {:error, reason}
    end
  end

  defp handle_client_request(state, %{"method" => "session/request_permission"} = payload) do
    case permission_response(state.session.settings, payload) do
      {:ok, response} ->
        _ = post_json_rpc_notification(state.connection, response)
        send_activity(state)
        {:cont, state}

      :error ->
        _ = post_json_rpc_notification(state.connection, permission_cancel_response(payload))

        Messages.emit(
          state.on_message,
          :turn_input_required,
          %{payload: payload, raw: Jason.encode!(payload)},
          PortMetadata.message(@provider_kind, state.session.port, payload, state.turn_context)
        )

        {:halt, {:error, {:turn_input_required, payload}}}
    end
  end

  defp handle_client_request(state, payload) do
    _ =
      post_json_rpc_notification(state.connection, %{
        "jsonrpc" => "2.0",
        "id" => Map.get(payload, "id"),
        "error" => %{"code" => -32_601, "message" => "ACP client method unsupported by Symphony CodeBuddy Phase 3"}
      })

    {:halt, {:error, {:client_request_unsupported, payload}}}
  end

  defp permission_response(%{permission_mode: "bypass_permissions"}, payload) do
    case preferred_allow_option_id(payload) do
      nil ->
        :error

      option_id ->
        {:ok,
         %{
           "jsonrpc" => "2.0",
           "id" => Map.get(payload, "id"),
           "result" => %{"outcome" => %{"outcome" => "selected", "optionId" => option_id}}
         }}
    end
  end

  defp permission_response(_settings, _payload), do: :error

  defp permission_cancel_response(payload) do
    %{"jsonrpc" => "2.0", "id" => Map.get(payload, "id"), "result" => %{"outcome" => %{"outcome" => "cancelled"}}}
  end

  defp preferred_allow_option_id(payload) do
    options = get_in(payload, ["params", "options"])

    case options do
      [_ | _] ->
        options
        |> Enum.filter(&(Map.get(&1, "optionId") && Map.get(&1, "kind") in ["allow_always", "allow_once"]))
        |> Enum.sort_by(fn option ->
          case Map.get(option, "kind") do
            "allow_always" -> 0
            "allow_once" -> 1
          end
        end)
        |> List.first()
        |> case do
          %{"optionId" => option_id} when is_binary(option_id) -> option_id
          _option -> nil
        end

      _options ->
        nil
    end
  end

  defp cancel_session(%{acp_http: connection, session_id: session_id}) when is_binary(session_id) do
    post_json_rpc_notification(connection, %{
      "jsonrpc" => "2.0",
      "method" => "session/cancel",
      "params" => %{"sessionId" => session_id}
    })
  end

  defp maybe_cancel_prompt_error(session, {:error, {:codebuddy_acp_http_transport_error, _details}}), do: cancel_session(session)
  defp maybe_cancel_prompt_error(session, {:error, :response_timeout}), do: cancel_session(session)
  defp maybe_cancel_prompt_error(_session, _result), do: :ok

  defp post_json_rpc_notification(%{request: request, endpoint_path: endpoint_path}, payload) do
    case Req.post(request,
           url: endpoint_path,
           json: payload,
           decode_body: false,
           headers: %{"accept" => "application/json, text/event-stream"}
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, http_error("POST", endpoint_path, status, body)}
      {:error, reason} -> {:error, transport_error("POST", endpoint_path, reason)}
    end
  end

  defp terminal_result(%{"stopReason" => "end_turn"} = result), do: {:ok, result}
  defp terminal_result(%{"stopReason" => "stop"} = result), do: {:ok, result}
  defp terminal_result(%{"stopReason" => reason} = result) when reason in ["cancelled", "canceled"], do: {:error, {:turn_cancelled, result}}
  defp terminal_result(%{"stopReason" => "input_required"} = result), do: {:error, {:turn_input_required, result}}
  defp terminal_result(%{"stopReason" => _reason} = result), do: {:error, {:turn_failed, result}}
  defp terminal_result(result), do: {:ok, result}

  defp emit_session_update(state, payload, payload_string) do
    update = get_in(payload, ["params", "update"]) || %{}

    case Map.get(update, "sessionUpdate") do
      "agent_message_chunk" ->
        emit_message_part(state, payload, payload_string, "text")

      "agent_thought_chunk" ->
        emit_message_part(state, payload, payload_string, "reasoning")

      update_type when update_type in ["tool_call", "tool_call_update"] ->
        Messages.emit(
          state.on_message,
          :tool_update,
          %{payload: payload, raw: payload_string},
          PortMetadata.message(@provider_kind, state.session.port, payload, state.turn_context)
        )

      _update_type ->
        Messages.emit(
          state.on_message,
          :notification,
          %{payload: payload, raw: payload_string},
          PortMetadata.message(@provider_kind, state.session.port, payload, state.turn_context)
        )
    end
  end

  defp emit_message_part(state, payload, payload_string, default_type) do
    update = get_in(payload, ["params", "update"]) || %{}
    content = Map.get(update, "content") || %{}
    text = Map.get(content, "text") || Map.get(update, "text") || ""
    message_id = Map.get(update, "messageId")

    part =
      %{
        "type" => default_type,
        "text" => text,
        "sessionID" => state.session.session_id
      }
      |> maybe_put("messageId", message_id)

    Messages.emit(
      state.on_message,
      "message.part.updated",
      %{
        payload: %{
          "payload" => %{
            "type" => "message.part.updated",
            "properties" => %{"part" => part}
          }
        },
        raw: payload_string
      },
      PortMetadata.message(@provider_kind, state.session.port, payload, state.turn_context)
    )
  end

  defp parse_sse_events(buffer, data) do
    normalized = (buffer <> IO.iodata_to_binary(data)) |> String.replace("\r\n", "\n")
    parts = String.split(normalized, "\n\n")

    {complete_parts, rest} =
      if String.ends_with?(normalized, "\n\n") do
        {parts, ""}
      else
        {Enum.drop(parts, -1), List.last(parts) || ""}
      end

    events =
      complete_parts
      |> Enum.map(&parse_sse_block/1)
      |> Enum.reject(&is_nil/1)

    {rest, events}
  end

  defp parse_sse_block(block) when is_binary(block) do
    lines = String.split(block, "\n", trim: true)

    data_lines =
      Enum.flat_map(lines, fn line ->
        if String.starts_with?(line, "data:") do
          [String.trim_leading(String.replace_prefix(line, "data:", ""))]
        else
          []
        end
      end)

    case data_lines do
      [] ->
        nil

      _lines ->
        case Jason.decode(Enum.join(data_lines, "\n")) do
          {:ok, %{} = decoded} -> decoded
          _decoded -> nil
        end
    end
  end

  defp receive_timeout_ms(started_at_ms, last_activity_ms, settings) do
    now_ms = EventFields.monotonic_ms()

    [
      remaining_timeout_ms(now_ms, started_at_ms, settings.turn_timeout_ms),
      remaining_timeout_ms(now_ms, last_activity_ms, settings.stall_timeout_ms)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> @poll_interval_ms end)
    |> max(@poll_interval_ms)
  end

  defp timeout_reason(started_at_ms, last_activity_ms, settings) do
    now_ms = EventFields.monotonic_ms()

    cond do
      timeout_expired?(now_ms, started_at_ms, settings.turn_timeout_ms) -> :turn_timeout
      timeout_expired?(now_ms, last_activity_ms, settings.stall_timeout_ms) -> :stall_timeout
      is_nil(last_activity_ms) and timeout_expired?(now_ms, started_at_ms, settings.read_timeout_ms) -> :turn_start_timeout
      true -> nil
    end
  end

  defp remaining_timeout_ms(_now_ms, nil, _timeout_ms), do: nil

  defp remaining_timeout_ms(now_ms, base_ms, timeout_ms)
       when is_integer(timeout_ms) and timeout_ms > 0 and is_integer(base_ms) do
    timeout_ms - max(now_ms - base_ms, 0)
  end

  defp remaining_timeout_ms(_now_ms, _base_ms, _timeout_ms), do: nil

  defp timeout_expired?(_now_ms, nil, _timeout_ms), do: false

  defp timeout_expired?(now_ms, base_ms, timeout_ms)
       when is_integer(timeout_ms) and timeout_ms > 0 and is_integer(base_ms) do
    now_ms - base_ms >= timeout_ms
  end

  defp timeout_expired?(_now_ms, _base_ms, _timeout_ms), do: false

  defp handshake_timeout_ms(settings), do: nested_timeout(settings, "handshake_timeout_ms", settings.read_timeout_ms)

  defp nested_timeout(settings, key, default_value) do
    case get_in(settings.acp, [key]) do
      value when is_integer(value) and value > 0 -> value
      _value -> default_value
    end
  end

  defp sleep_or_timeout(deadline_ms, timeout_reason, next_fun) do
    if EventFields.monotonic_ms() >= deadline_ms do
      timeout_reason.()
    else
      Process.sleep(@poll_interval_ms)
      next_fun.()
    end
  end

  defp send_activity(%{turn_ref: turn_ref, owner: owner}) when is_reference(turn_ref) and is_pid(owner) do
    send(owner, {turn_ref, :activity, EventFields.monotonic_ms()})
  end

  defp send_activity(_state), do: :ok

  defp turn_context(session, issue) do
    %{
      issue: issue,
      run_id: session.run_id,
      session_id: session.session_id,
      thread_id: session.thread_id,
      workspace: session.workspace,
      worker_host: session.worker_host
    }
  end

  defp http_error(method, path, status, body) do
    {:codebuddy_acp_http_error,
     %{
       method: method,
       path: path,
       response_status: status,
       response_body: preview(body)
     }}
  end

  defp transport_error(method, path, reason) do
    {:codebuddy_acp_http_transport_error,
     %{
       method: method,
       path: path,
       reason: preview(reason)
     }}
  end

  defp preview(value), do: Redaction.summarize(value, 256)

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

  defp redact_meta(%{} = payload) do
    Enum.reduce(payload, %{}, fn
      {"_meta", meta}, acc -> Map.put(acc, "_meta", redact_codebuddy_meta(meta))
      {key, value}, acc when is_map(value) -> Map.put(acc, key, redact_meta(value))
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp redact_codebuddy_meta(meta) when is_map(meta) do
    meta
    |> Enum.map(fn {key, value} -> {key, redact_meta_value(key, value)} end)
    |> Map.new()
  end

  defp redact_codebuddy_meta(_meta), do: "<redacted>"

  defp redact_meta_value(key, value) when key in ["codebuddy.ai/finishReason"], do: value
  defp redact_meta_value(_key, _value), do: "<redacted>"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
