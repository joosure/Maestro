defmodule SymphonyElixir.AgentProvider.Codex.AppServer.TurnStream do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.AppServer.PortMetadata
  alias SymphonyElixir.AgentProvider.Codex.AppServer.EventFields
  alias SymphonyElixir.AgentProvider.Codex.AppServer.Messages
  alias SymphonyElixir.AgentProvider.Codex.AppServer.StreamDiagnostics
  alias SymphonyElixir.AgentProvider.Codex.AppServer.TurnRequests
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @spec await_completion(term(), (map() -> term()), boolean(), map(), pos_integer()) ::
          {:ok, :turn_completed} | {:error, term()}
  def await_completion(
        port,
        on_message,
        auto_approve_requests,
        turn_context,
        turn_timeout_ms
      ) do
    receive_loop(
      port,
      on_message,
      turn_timeout_ms,
      "",
      auto_approve_requests,
      turn_context
    )
  end

  defp receive_loop(
         port,
         on_message,
         timeout_ms,
         pending_line,
         auto_approve_requests,
         turn_context
       ) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> to_string(chunk)

        handle_incoming(
          port,
          on_message,
          complete_line,
          timeout_ms,
          auto_approve_requests,
          turn_context
        )

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(
          port,
          on_message,
          timeout_ms,
          pending_line <> to_string(chunk),
          auto_approve_requests,
          turn_context
        )

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout_ms ->
        {:error, :turn_timeout}
    end
  end

  defp handle_incoming(
         port,
         on_message,
         data,
         timeout_ms,
         auto_approve_requests,
         turn_context
       ) do
    payload_string = to_string(data)

    case Jason.decode(payload_string) do
      {:ok, %{"method" => "turn/completed"} = payload} ->
        emit_turn_event(on_message, :turn_completed, payload, payload_string, port, payload, turn_context)
        {:ok, :turn_completed}

      {:ok, %{"method" => "turn/failed", "params" => _} = payload} ->
        emit_turn_event(
          on_message,
          :turn_failed,
          payload,
          payload_string,
          port,
          Map.get(payload, "params"),
          turn_context
        )

        {:error, {:turn_failed, Map.get(payload, "params")}}

      {:ok, %{"method" => "turn/cancelled", "params" => _} = payload} ->
        emit_turn_event(
          on_message,
          :turn_cancelled,
          payload,
          payload_string,
          port,
          Map.get(payload, "params"),
          turn_context
        )

        {:error, {:turn_cancelled, Map.get(payload, "params")}}

      {:ok, %{"method" => "error"} = payload} ->
        reason = codex_error_reason(payload)
        emit_turn_event(on_message, :codex_error, payload, payload_string, port, reason, turn_context)
        {:error, {:codex_error, reason}}

      {:ok, %{"method" => method} = payload}
      when is_binary(method) ->
        handle_turn_method(
          port,
          on_message,
          payload,
          payload_string,
          method,
          timeout_ms,
          auto_approve_requests,
          turn_context
        )

      {:ok, payload} ->
        Messages.emit(
          on_message,
          :other_message,
          %{
            payload: payload,
            raw: payload_string
          },
          PortMetadata.message("codex", port, payload, turn_context)
        )

        receive_loop(
          port,
          on_message,
          timeout_ms,
          "",
          auto_approve_requests,
          turn_context
        )

      {:error, _reason} ->
        stream_event = StreamDiagnostics.log_turn_line(payload_string, "turn stream", turn_context)

        if StreamDiagnostics.protocol_message_candidate?(payload_string) do
          ObsLogger.emit(
            :warning,
            :codex_stream_malformed,
            EventFields.turn(turn_context, %{
              stream_label: "turn stream",
              payload_summary: EventFields.stream_summary(payload_string),
              error: "invalid_json"
            })
          )

          Messages.emit(
            on_message,
            :malformed,
            %{
              payload: payload_string,
              raw: payload_string
            },
            PortMetadata.message("codex", port, %{raw: payload_string}, turn_context)
          )
        else
          emit_non_json_stream_message(
            on_message,
            stream_event,
            payload_string,
            port,
            turn_context
          )
        end

        receive_loop(
          port,
          on_message,
          timeout_ms,
          "",
          auto_approve_requests,
          turn_context
        )
    end
  end

  defp emit_turn_event(on_message, event, payload, payload_string, port, payload_details, turn_context) do
    Messages.emit(
      on_message,
      event,
      %{
        payload: payload,
        raw: payload_string,
        details: payload_details
      },
      PortMetadata.message("codex", port, payload, turn_context)
    )
  end

  defp codex_error_reason(%{"params" => params}) when is_map(params), do: params
  defp codex_error_reason(%{"error" => error}) when is_map(error), do: error
  defp codex_error_reason(payload), do: payload

  defp handle_turn_method(
         port,
         on_message,
         payload,
         payload_string,
         method,
         timeout_ms,
         auto_approve_requests,
         turn_context
       ) do
    metadata = PortMetadata.message("codex", port, payload, turn_context)

    case TurnRequests.handle(%{
           port: port,
           method: method,
           payload: payload,
           payload_string: payload_string,
           on_message: on_message,
           metadata: metadata,
           auto_approve_requests: auto_approve_requests,
           turn_context: turn_context
         }) do
      :input_required ->
        ObsLogger.emit(
          :warning,
          :codex_input_required,
          EventFields.turn(turn_context, %{
            payload_summary: EventFields.stream_summary(payload),
            policy_action: "turn_input_required"
          })
        )

        Messages.emit(
          on_message,
          :turn_input_required,
          %{payload: payload, raw: payload_string},
          metadata
        )

        {:error, {:turn_input_required, payload}}

      :approved ->
        receive_loop(
          port,
          on_message,
          timeout_ms,
          "",
          auto_approve_requests,
          turn_context
        )

      :approval_required ->
        ObsLogger.emit(
          :warning,
          :codex_approval_requested,
          EventFields.turn(turn_context, %{
            payload_summary: EventFields.stream_summary(payload),
            policy_action: "approval_required"
          })
        )

        Messages.emit(
          on_message,
          :approval_required,
          %{payload: payload, raw: payload_string},
          metadata
        )

        {:error, {:approval_required, payload}}

      :unhandled ->
        if TurnRequests.needs_input?(method, payload) do
          ObsLogger.emit(
            :warning,
            :codex_input_required,
            EventFields.turn(turn_context, %{
              payload_summary: EventFields.stream_summary(payload),
              policy_action: "notification_input_required"
            })
          )

          Messages.emit(
            on_message,
            :turn_input_required,
            %{payload: payload, raw: payload_string},
            metadata
          )

          {:error, {:turn_input_required, payload}}
        else
          Messages.emit(
            on_message,
            :notification,
            %{
              payload: payload,
              raw: payload_string
            },
            metadata
          )

          receive_loop(
            port,
            on_message,
            timeout_ms,
            "",
            auto_approve_requests,
            turn_context
          )
        end
    end
  end

  defp emit_non_json_stream_message(
         on_message,
         {event, text, stream_label},
         raw_payload,
         port,
         turn_context
       )
       when event in [:stream_output, :stream_warning] and is_binary(text) and is_binary(stream_label) do
    Messages.emit(
      on_message,
      event,
      %{
        payload: text,
        raw: raw_payload,
        stream_label: stream_label
      },
      PortMetadata.message("codex", port, %{raw: raw_payload}, turn_context)
    )
  end

  defp emit_non_json_stream_message(_on_message, _event, _raw_payload, _port, _turn_context), do: :ok
end
