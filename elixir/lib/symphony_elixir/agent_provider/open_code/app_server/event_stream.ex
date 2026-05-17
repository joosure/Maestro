defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.EventStream do
  @moduledoc false

  require Logger

  alias SymphonyElixir.AgentProvider.AppServer.Messages
  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.{Context, Diagnostics, Paths, Usage}
  alias SymphonyElixir.PathSafety

  @allowed_unattended_permissions MapSet.new(~w(read edit glob grep list bash lsp task skill todowrite webfetch websearch codesearch))
  @stream_idle_poll_ms 250

  @spec stream_session_events(map(), reference(), pid(), (map() -> term())) :: :ok
  def stream_session_events(session, turn_ref, owner, on_message)
      when is_map(session) and is_reference(turn_ref) and is_pid(owner) and is_function(on_message, 1) do
    response =
      Req.get!(session.request,
        url: Paths.global_event(),
        decode_body: false,
        into: :self,
        headers: %{"accept" => "text/event-stream"}
      )

    receive_stream_events(response, "", session, turn_ref, owner, on_message)
  end

  defp receive_stream_events(response, buffer, session, turn_ref, owner, on_message) do
    receive do
      message ->
        case Req.parse_message(response, message) do
          {:ok, chunks} ->
            {next_buffer, continue?} =
              Enum.reduce_while(chunks, {buffer, true}, fn chunk, {buffer_acc, _continue?} ->
                case handle_stream_chunk(chunk, buffer_acc, session, turn_ref, owner, on_message) do
                  {:cont, next_buffer} -> {:cont, {next_buffer, true}}
                  {:halt, next_buffer} -> {:halt, {next_buffer, false}}
                end
              end)

            if continue?, do: receive_stream_events(response, next_buffer, session, turn_ref, owner, on_message)

          :unknown ->
            receive_stream_events(response, buffer, session, turn_ref, owner, on_message)

          {:error, reason} ->
            unless stream_closed?(reason) do
              send(owner, {turn_ref, :stream_error, event_stream_error(session, reason)})
            end

            :ok
        end
    after
      @stream_idle_poll_ms ->
        receive_stream_events(response, buffer, session, turn_ref, owner, on_message)
    end
  end

  defp handle_stream_chunk({:data, data}, buffer, session, turn_ref, owner, on_message) do
    {next_buffer, events} = parse_sse_events(buffer, data)
    Enum.each(events, &handle_global_event(&1, session, turn_ref, owner, on_message))
    {:cont, next_buffer}
  end

  defp handle_stream_chunk(:done, buffer, _session, _turn_ref, _owner, _on_message), do: {:halt, buffer}
  defp handle_stream_chunk(_chunk, buffer, _session, _turn_ref, _owner, _on_message), do: {:cont, buffer}

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

    {event_name, data_lines} =
      Enum.reduce(lines, {nil, []}, fn line, {event_name_acc, data_acc} ->
        cond do
          String.starts_with?(line, "event:") ->
            {String.trim(String.replace_prefix(line, "event:", "")), data_acc}

          String.starts_with?(line, "data:") ->
            {event_name_acc, data_acc ++ [String.trim_leading(String.replace_prefix(line, "data:", ""))]}

          true ->
            {event_name_acc, data_acc}
        end
      end)

    case Jason.decode(Enum.join(data_lines, "\n")) do
      {:ok, %{} = decoded} -> %{"event" => event_name, "payload" => decoded}
      _decoded -> nil
    end
  end

  defp handle_global_event(
         %{"payload" => %{"payload" => %{"type" => type, "properties" => properties}} = envelope},
         session,
         turn_ref,
         owner,
         on_message
       ) do
    if event_matches_session?(properties, session.session_id) do
      now_ms = monotonic_ms()
      send(owner, {turn_ref, :activity, now_ms})
      usage = Usage.event_usage(type, properties)

      Messages.emit(
        on_message,
        type,
        %{session_id: session.session_id, thread_id: session.thread_id, payload: envelope, usage: usage},
        session.metadata
      )

      maybe_handle_runtime_event(type, properties, session, turn_ref, owner)
    end
  end

  defp handle_global_event(_event, _session, _turn_ref, _owner, _on_message), do: :ok

  defp maybe_handle_runtime_event("permission.asked", properties, session, _turn_ref, _owner) do
    decision = permission_reply(properties, session.workspace)
    reply_permission_request(session.request, session.session_id, properties, decision)
  end

  defp maybe_handle_runtime_event("question.asked", properties, session, turn_ref, owner) do
    reject_question_request(session.request, properties)
    send(owner, {turn_ref, :turn_failed, {:turn_input_required, properties}})
  end

  defp maybe_handle_runtime_event("session.error", properties, _session, turn_ref, owner),
    do: send(owner, {turn_ref, :turn_failed, {:session_error, properties}})

  defp maybe_handle_runtime_event("message.updated", %{"info" => %{"error" => error}}, _session, turn_ref, owner)
       when not is_nil(error),
       do: send(owner, {turn_ref, :turn_failed, {:message_error, error}})

  defp maybe_handle_runtime_event(_type, _properties, _session, _turn_ref, _owner), do: :ok

  defp event_matches_session?(properties, expected_session_id) do
    case event_session_id(properties) do
      session_id when is_binary(session_id) -> session_id == expected_session_id
      _session_id -> false
    end
  end

  defp event_session_id(%{"sessionID" => session_id}) when is_binary(session_id), do: session_id
  defp event_session_id(%{sessionID: session_id}) when is_binary(session_id), do: session_id
  defp event_session_id(%{"info" => %{"sessionID" => session_id}}) when is_binary(session_id), do: session_id
  defp event_session_id(%{info: %{sessionID: session_id}}) when is_binary(session_id), do: session_id
  defp event_session_id(%{"part" => %{"sessionID" => session_id}}) when is_binary(session_id), do: session_id
  defp event_session_id(%{part: %{sessionID: session_id}}) when is_binary(session_id), do: session_id
  defp event_session_id(_properties), do: nil

  defp reply_permission_request(request, session_id, properties, decision) do
    permission_id = Map.get(properties, "id") || Map.get(properties, :id)

    if is_binary(permission_id) do
      case Req.post(request, url: "/session/#{session_id}/permissions/#{permission_id}", json: %{"response" => decision}) do
        {:ok, _response} -> :ok
        {:error, reason} -> Logger.debug("OpenCode permission reply failed: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp reject_question_request(request, properties) do
    request_id = Map.get(properties, "id") || Map.get(properties, :id)

    if is_binary(request_id) do
      case Req.post(request, url: "/question/#{request_id}/reject", json: %{}) do
        {:ok, _response} -> :ok
        {:error, reason} -> Logger.debug("OpenCode question reject failed: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp permission_reply(properties, workspace) do
    permission = Map.get(properties, "permission") || Map.get(properties, :permission)

    cond do
      permission == "external_directory" -> "reject"
      permission not in @allowed_unattended_permissions -> "reject"
      permission_patterns_within_workspace?(properties, workspace) -> "once"
      true -> "reject"
    end
  end

  defp permission_patterns_within_workspace?(properties, workspace) do
    patterns = Map.get(properties, "patterns") || Map.get(properties, :patterns) || []
    patterns != [] and Enum.all?(patterns, &pattern_within_workspace?(&1, workspace))
  end

  defp pattern_within_workspace?(pattern, workspace) when is_binary(pattern) and is_binary(workspace) do
    trimmed = String.trim(pattern)

    cond do
      trimmed == "" -> false
      String.contains?(trimmed, ["\n", "\r", <<0>>]) -> false
      Path.type(trimmed) == :absolute -> absolute_scope_within_workspace?(trimmed, workspace)
      true -> relative_scope_within_workspace?(trimmed, workspace)
    end
  end

  defp pattern_within_workspace?(_pattern, _workspace), do: false

  defp absolute_scope_within_workspace?(pattern, workspace) do
    with {:ok, canonical_workspace} <- PathSafety.canonicalize(workspace),
         prefix <- wildcard_free_prefix(pattern),
         {:ok, canonical_prefix} <- PathSafety.canonicalize(prefix) do
      canonical_prefix == canonical_workspace or String.starts_with?(canonical_prefix <> "/", canonical_workspace <> "/")
    else
      _reason -> false
    end
  end

  defp relative_scope_within_workspace?(pattern, workspace) do
    with {:ok, canonical_workspace} <- PathSafety.canonicalize(workspace),
         prefix <- wildcard_free_prefix(pattern),
         expanded_prefix <- Path.expand(prefix, workspace),
         {:ok, canonical_prefix} <- PathSafety.canonicalize(expanded_prefix) do
      canonical_prefix == canonical_workspace or String.starts_with?(canonical_prefix <> "/", canonical_workspace <> "/")
    else
      _reason -> false
    end
  end

  defp wildcard_free_prefix(pattern) do
    pattern
    |> String.split(~r/[*?{\[]/, parts: 2)
    |> List.first()
    |> then(fn prefix -> if prefix in [nil, ""], do: ".", else: prefix end)
  end

  defp event_stream_error(session, reason) do
    transport_reason = mint_transport_reason(reason)

    kind =
      if transport_reason == :timeout,
        do: :event_stream_timeout,
        else: :event_stream_failed

    message =
      if transport_reason == :timeout,
        do: "OpenCode event stream did not deliver data before read_timeout_ms elapsed",
        else: "OpenCode event stream failed while reading or parsing SSE events"

    {kind,
     Map.merge(Context.session(session), %{
       method: "GET",
       path: Paths.global_event(),
       transport_reason: transport_reason,
       cause: Diagnostics.preview_value(reason),
       message: message
     })}
  end

  defp mint_transport_reason(%Mint.TransportError{reason: reason}), do: reason
  defp mint_transport_reason(_reason), do: nil

  defp stream_closed?(%Mint.TransportError{reason: :closed}), do: true
  defp stream_closed?(_reason), do: false

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
