defmodule SymphonyElixir.AgentProvider.ClaudeCode.AppServer.StreamProtocol do
  @moduledoc false

  require Logger

  alias SymphonyElixir.Agent.Runtime.Handle
  alias SymphonyElixir.AgentProvider.AppServer.Messages
  alias SymphonyElixir.AgentProvider.ClaudeCode.AppServer.{ProcessLifecycle, Usage}

  @poll_interval_ms 250
  @max_stream_log_bytes 1_000

  @spec send_turn_input(term(), String.t()) :: :ok | {:error, term()}
  def send_turn_input(port, prompt) when is_binary(prompt) do
    payload =
      Jason.encode!(%{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => prompt
        }
      }) <> "\n"

    try do
      if Handle.alive?(port) and Handle.command(port, payload) do
        :ok
      else
        {:error, :port_closed}
      end
    rescue
      ArgumentError ->
        {:error, :port_closed}
    end
  end

  @spec await_turn_result(map(), (map() -> term()), integer()) :: {:ok, map()} | {:error, term()}
  def await_turn_result(session, on_message, started_at_ms)
      when is_map(session) and is_function(on_message, 1) and is_integer(started_at_ms) do
    await_turn_result(session, on_message, started_at_ms, nil, nil, "")
  end

  defp await_turn_result(session, on_message, started_at_ms, first_activity_ms, last_activity_ms, pending_line) do
    receive do
      {port, {:data, {:eol, chunk}}} when port == session.port ->
        line = pending_line <> IO.chardata_to_string(chunk)

        case handle_stream_line(line, session, on_message) do
          {:continue, activity?} ->
            now_ms = monotonic_ms()

            await_turn_result(
              session,
              on_message,
              started_at_ms,
              first_activity_ms || if(activity?, do: now_ms),
              if(activity?, do: now_ms, else: last_activity_ms),
              ""
            )

          {:done, response} ->
            {:ok, response}

          {:error, reason} ->
            {:error, reason}
        end

      {port, {:data, {:noeol, chunk}}} when port == session.port ->
        await_turn_result(
          session,
          on_message,
          started_at_ms,
          first_activity_ms,
          last_activity_ms,
          pending_line <> IO.chardata_to_string(chunk)
        )

      {port, {:exit_status, status}} when port == session.port ->
        {:error, {:port_exit, status}}
    after
      @poll_interval_ms ->
        now_ms = monotonic_ms()
        settings = session.settings

        cond do
          settings.turn_timeout_ms > 0 and now_ms - started_at_ms > settings.turn_timeout_ms ->
            ProcessLifecycle.stop_port(session.port)
            {:error, :turn_timeout}

          settings.read_timeout_ms > 0 and is_nil(first_activity_ms) and now_ms - started_at_ms > settings.read_timeout_ms ->
            ProcessLifecycle.stop_port(session.port)
            {:error, :turn_start_timeout}

          settings.stall_timeout_ms > 0 and is_integer(last_activity_ms) and now_ms - last_activity_ms > settings.stall_timeout_ms ->
            ProcessLifecycle.stop_port(session.port)
            {:error, :stall_timeout}

          true ->
            await_turn_result(session, on_message, started_at_ms, first_activity_ms, last_activity_ms, pending_line)
        end
    end
  end

  defp handle_stream_line(line, session, on_message) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "result"} = payload} ->
        if result_success?(payload), do: {:done, payload}, else: {:error, {:claude_result_error, payload}}

      {:ok, %{"type" => "assistant"} = payload} ->
        emit_assistant_updates(on_message, session, payload)
        {:continue, true}

      {:ok, %{"type" => "system", "subtype" => "init"} = payload} ->
        maybe_log_session_mismatch(session.session_id, payload["session_id"])
        {:continue, true}

      {:ok, %{} = _payload} ->
        {:continue, true}

      {:error, _reason} ->
        log_non_json_stream_line(line)
        {:continue, false}
    end
  end

  defp emit_assistant_updates(on_message, session, payload) do
    usage = Usage.assistant_usage(payload)

    payload
    |> assistant_content_items()
    |> Enum.map(&assistant_part_payload(&1, usage, session.session_id))
    |> Enum.each(fn part_payload ->
      Messages.emit(
        on_message,
        "message.part.updated",
        %{session_id: session.session_id, thread_id: session.thread_id, payload: part_payload, usage: usage},
        session.metadata
      )
    end)
  end

  defp assistant_content_items(%{"message" => %{"content" => content}}) when is_list(content), do: content
  defp assistant_content_items(%{message: %{content: content}}) when is_list(content), do: content
  defp assistant_content_items(_payload), do: []

  defp assistant_part_payload(%{"type" => "text", "text" => text}, usage, session_id) when is_binary(text),
    do: part_payload(%{"type" => "text", "text" => text}, usage, session_id)

  defp assistant_part_payload(%{"type" => type, "text" => text}, usage, session_id)
       when type in ["thinking", "reasoning"] and is_binary(text),
       do: part_payload(%{"type" => "reasoning", "text" => text}, usage, session_id)

  defp assistant_part_payload(%{"type" => "tool_use", "name" => name}, usage, session_id) when is_binary(name),
    do: part_payload(%{"type" => "tool", "tool" => name, "state" => %{"status" => "running"}}, usage, session_id)

  defp assistant_part_payload(part, usage, session_id),
    do: part_payload(%{"type" => "text", "text" => Jason.encode!(part)}, usage, session_id)

  defp part_payload(part, usage, session_id) do
    part =
      part
      |> Map.put("sessionID", session_id)
      |> maybe_put_tokens(usage)

    %{
      "payload" => %{
        "type" => "message.part.updated",
        "properties" => %{
          "part" => part
        }
      }
    }
  end

  defp maybe_put_tokens(part, usage) when is_map(usage), do: Map.put(part, "tokens", usage)
  defp maybe_put_tokens(part, _usage), do: part

  defp result_success?(%{"is_error" => true}), do: false
  defp result_success?(%{"subtype" => "success"}), do: true
  defp result_success?(_payload), do: false

  defp maybe_log_session_mismatch(expected_session_id, actual_session_id)
       when is_binary(expected_session_id) and is_binary(actual_session_id) and expected_session_id != actual_session_id do
    Logger.warning("Claude Code session ID mismatch expected=#{expected_session_id} actual=#{actual_session_id}")
  end

  defp maybe_log_session_mismatch(_expected_session_id, _actual_session_id), do: :ok

  defp log_non_json_stream_line(text) when is_binary(text) do
    text = text |> String.trim() |> truncate_output()
    if text != "", do: Logger.debug("Claude Code stream output: #{text}")
  end

  defp truncate_output(text) when byte_size(text) > @max_stream_log_bytes, do: binary_part(text, 0, @max_stream_log_bytes) <> "..."
  defp truncate_output(text), do: text

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
