defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.Protocol do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Handle
  alias SymphonyElixir.AgentProvider.AppServer.{Messages, PortMetadata}
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.{EventFields, ProcessLifecycle}
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @provider_kind Kinds.codebuddy_code()
  @initialize_id 0
  @session_new_id 1
  @prompt_id 2
  @poll_interval_ms 250

  @spec initialize(term(), map()) :: {:ok, map()} | {:error, term()}
  def initialize(port, settings) do
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

    with :ok <- send_message(port, payload) do
      await_response(port, @initialize_id, handshake_timeout_ms(settings))
    end
  end

  @spec new_session(term(), Path.t(), map()) :: {:ok, map()} | {:error, term()}
  def new_session(port, workspace, settings) when is_binary(workspace) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => @session_new_id,
      "method" => "session/new",
      "params" => %{
        "cwd" => workspace,
        "mcpServers" => []
      }
    }

    with :ok <- send_message(port, payload),
         {:ok, %{"sessionId" => session_id} = response} when is_binary(session_id) <-
           await_response(port, @session_new_id, read_timeout_ms(settings)) do
      {:ok, response}
    else
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

    started_at_ms = EventFields.monotonic_ms()
    turn_context = turn_context(session, issue)

    with :ok <- send_message(session.port, payload) do
      await_prompt_response(session, on_message, turn_context, started_at_ms, nil, "")
    end
  end

  @spec send_message(term(), map()) :: :ok | {:error, term()}
  def send_message(port, message) when is_map(message) do
    line = Jason.encode!(message) <> "\n"

    try do
      if Handle.alive?(port) and Handle.command(port, line) do
        :ok
      else
        {:error, :port_closed}
      end
    rescue
      ArgumentError ->
        {:error, :port_closed}
    end
  end

  @spec redacted_meta(map()) :: map()
  def redacted_meta(%{} = payload) do
    payload
    |> Map.take(["stopReason", "_meta"])
    |> redact_meta()
  end

  def redacted_meta(_payload), do: %{}

  defp await_response(port, request_id, timeout_ms), do: await_response(port, request_id, timeout_ms, "")

  defp await_response(port, request_id, timeout_ms, pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> to_string(chunk)
        handle_response_line(port, request_id, complete_line, timeout_ms)

      {^port, {:data, {:noeol, chunk}}} ->
        await_response(port, request_id, timeout_ms, pending_line <> to_string(chunk))

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout_ms ->
        {:error, :response_timeout}
    end
  end

  defp handle_response_line(port, request_id, line, timeout_ms) do
    case Jason.decode(to_string(line)) do
      {:ok, %{"id" => ^request_id, "error" => error}} ->
        {:error, {:response_error, error}}

      {:ok, %{"id" => ^request_id, "result" => result}} ->
        {:ok, result}

      {:ok, %{"id" => ^request_id} = payload} ->
        {:error, {:response_error, payload}}

      {:ok, %{} = payload} ->
        ObsLogger.emit(
          :debug,
          :codebuddy_code_response_ignored,
          %{component: "agent_provider.codebuddy_code", agent_provider_kind: @provider_kind, payload_summary: EventFields.stream_summary(payload)}
        )

        await_response(port, request_id, timeout_ms, "")

      {:error, _reason} ->
        await_response(port, request_id, timeout_ms, "")
    end
  end

  defp await_prompt_response(session, on_message, turn_context, started_at_ms, last_activity_ms, pending_line) do
    case timeout_reason(started_at_ms, last_activity_ms, session.settings) do
      nil ->
        receive do
          {port, {:data, {:eol, chunk}}} when port == session.port ->
            complete_line = pending_line <> to_string(chunk)
            activity_ms = EventFields.monotonic_ms()

            handle_prompt_line(session, on_message, turn_context, complete_line, started_at_ms, activity_ms)

          {port, {:data, {:noeol, chunk}}} when port == session.port ->
            await_prompt_response(session, on_message, turn_context, started_at_ms, last_activity_ms, pending_line <> to_string(chunk))

          {port, {:exit_status, status}} when port == session.port ->
            {:error, {:port_exit, status}}
        after
          receive_timeout_ms(started_at_ms, last_activity_ms, session.settings) ->
            timeout = timeout_reason(started_at_ms, last_activity_ms, session.settings) || :turn_timeout
            ProcessLifecycle.stop_port(session.port)
            {:error, timeout}
        end

      reason ->
        ProcessLifecycle.stop_port(session.port)
        {:error, reason}
    end
  end

  defp handle_prompt_line(session, on_message, turn_context, line, started_at_ms, activity_ms) do
    payload_string = to_string(line)

    case Jason.decode(payload_string) do
      {:ok, %{"id" => @prompt_id, "error" => error}} ->
        {:error, {:response_error, error}}

      {:ok, %{"id" => @prompt_id, "result" => %{} = result}} ->
        terminal_result(result)

      {:ok, %{"id" => @prompt_id} = payload} ->
        {:error, {:response_error, payload}}

      {:ok, %{"id" => _id, "method" => method} = payload} when is_binary(method) ->
        handle_client_request(session, on_message, turn_context, payload)

      {:ok, %{"method" => "session/update"} = payload} ->
        emit_session_update(session, on_message, turn_context, payload, payload_string)
        await_prompt_response(session, on_message, turn_context, started_at_ms, activity_ms, "")

      {:ok, %{"method" => method} = payload} when is_binary(method) ->
        Messages.emit(
          on_message,
          :notification,
          %{payload: payload, raw: payload_string},
          PortMetadata.message(@provider_kind, session.port, payload, turn_context)
        )

        await_prompt_response(session, on_message, turn_context, started_at_ms, activity_ms, "")

      {:ok, payload} ->
        Messages.emit(
          on_message,
          :notification,
          %{payload: payload, raw: payload_string},
          PortMetadata.message(@provider_kind, session.port, %{payload: payload}, turn_context)
        )

        await_prompt_response(session, on_message, turn_context, started_at_ms, activity_ms, "")

      {:error, _reason} ->
        Messages.emit(
          on_message,
          :malformed,
          %{payload: payload_string, raw: payload_string},
          PortMetadata.message(@provider_kind, session.port, %{raw: payload_string}, turn_context)
        )

        await_prompt_response(session, on_message, turn_context, started_at_ms, activity_ms, "")
    end
  end

  defp terminal_result(%{"stopReason" => "end_turn"} = result), do: {:ok, result}
  defp terminal_result(%{"stopReason" => "stop"} = result), do: {:ok, result}
  defp terminal_result(%{"stopReason" => reason} = result) when reason in ["cancelled", "canceled"], do: {:error, {:turn_cancelled, result}}
  defp terminal_result(%{"stopReason" => "input_required"} = result), do: {:error, {:turn_input_required, result}}
  defp terminal_result(%{"stopReason" => _reason} = result), do: {:error, {:turn_failed, result}}
  defp terminal_result(result), do: {:ok, result}

  defp handle_client_request(session, on_message, turn_context, %{"method" => "session/request_permission"} = payload) do
    _ = send_message(session.port, %{"jsonrpc" => "2.0", "id" => Map.get(payload, "id"), "result" => %{"outcome" => %{"outcome" => "cancelled"}}})

    Messages.emit(
      on_message,
      :turn_input_required,
      %{payload: payload, raw: Jason.encode!(payload)},
      PortMetadata.message(@provider_kind, session.port, payload, turn_context)
    )

    {:error, {:turn_input_required, payload}}
  end

  defp handle_client_request(session, _on_message, _turn_context, payload) do
    _ =
      send_message(session.port, %{
        "jsonrpc" => "2.0",
        "id" => Map.get(payload, "id"),
        "error" => %{"code" => -32_601, "message" => "ACP client method unsupported by the Symphony CodeBuddy baseline"}
      })

    {:error, {:client_request_unsupported, payload}}
  end

  defp emit_session_update(session, on_message, turn_context, payload, payload_string) do
    update = get_in(payload, ["params", "update"]) || %{}

    case Map.get(update, "sessionUpdate") do
      "agent_message_chunk" ->
        emit_message_part(session, on_message, turn_context, payload, payload_string, "text")

      "agent_thought_chunk" ->
        emit_message_part(session, on_message, turn_context, payload, payload_string, "reasoning")

      update_type when update_type in ["tool_call", "tool_call_update"] ->
        Messages.emit(
          on_message,
          :tool_update,
          %{payload: payload, raw: payload_string},
          PortMetadata.message(@provider_kind, session.port, payload, turn_context)
        )

      _update_type ->
        Messages.emit(
          on_message,
          :notification,
          %{payload: payload, raw: payload_string},
          PortMetadata.message(@provider_kind, session.port, payload, turn_context)
        )
    end
  end

  defp emit_message_part(session, on_message, turn_context, payload, payload_string, default_type) do
    update = get_in(payload, ["params", "update"]) || %{}
    content = Map.get(update, "content") || %{}
    text = Map.get(content, "text") || Map.get(update, "text") || ""
    message_id = Map.get(update, "messageId")

    part =
      %{
        "type" => default_type,
        "text" => text,
        "sessionID" => session.session_id
      }
      |> maybe_put("messageId", message_id)

    Messages.emit(
      on_message,
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
      PortMetadata.message(@provider_kind, session.port, payload, turn_context)
    )
  end

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
  defp read_timeout_ms(settings), do: settings.read_timeout_ms

  defp nested_timeout(settings, key, default_value) do
    case get_in(settings.acp, [key]) do
      value when is_integer(value) and value > 0 -> value
      _value -> default_value
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
