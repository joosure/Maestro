defmodule SymphonyElixir.AgentProvider.Codex.AppServer.TurnStream do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.AppServer.PortMetadata
  alias SymphonyElixir.AgentProvider.Codex.AppServer.EventFields
  alias SymphonyElixir.AgentProvider.Codex.AppServer.Messages
  alias SymphonyElixir.AgentProvider.Codex.AppServer.StreamDiagnostics
  alias SymphonyElixir.AgentProvider.Codex.AppServer.TurnRequests
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @provider_kind Kinds.codex()

  @spec await_completion(term(), (map() -> term()), boolean(), map(), pos_integer(), non_neg_integer() | nil) ::
          {:ok, :turn_completed} | {:error, term()}
  def await_completion(
        port,
        on_message,
        auto_approve_requests,
        turn_context,
        turn_timeout_ms,
        stall_timeout_ms
      ) do
    now_ms = monotonic_ms()

    receive_loop(
      port,
      on_message,
      "",
      auto_approve_requests,
      turn_context,
      now_ms,
      now_ms,
      turn_timeout_ms,
      stall_timeout_ms
    )
  end

  defp receive_loop(
         port,
         on_message,
         pending_line,
         auto_approve_requests,
         turn_context,
         started_at_ms,
         last_activity_ms,
         turn_timeout_ms,
         stall_timeout_ms
       ) do
    now_ms = monotonic_ms()

    case timeout_reason(now_ms, started_at_ms, last_activity_ms, turn_timeout_ms, stall_timeout_ms) do
      nil ->
        receive_timeout_ms = receive_timeout_ms(now_ms, started_at_ms, last_activity_ms, turn_timeout_ms, stall_timeout_ms)

        receive do
          {^port, {:data, {:eol, chunk}}} ->
            activity_ms = monotonic_ms()
            complete_line = pending_line <> to_string(chunk)

            handle_incoming(
              port,
              on_message,
              complete_line,
              auto_approve_requests,
              turn_context,
              started_at_ms,
              activity_ms,
              turn_timeout_ms,
              stall_timeout_ms
            )

          {^port, {:data, {:noeol, chunk}}} ->
            receive_loop(
              port,
              on_message,
              pending_line <> to_string(chunk),
              auto_approve_requests,
              turn_context,
              started_at_ms,
              monotonic_ms(),
              turn_timeout_ms,
              stall_timeout_ms
            )

          {^port, {:exit_status, status}} ->
            {:error, {:port_exit, status}}
        after
          receive_timeout_ms ->
            {:error,
             timeout_reason(monotonic_ms(), started_at_ms, last_activity_ms, turn_timeout_ms, stall_timeout_ms) ||
               :turn_timeout}
        end

      reason ->
        {:error, reason}
    end
  end

  defp handle_incoming(
         port,
         on_message,
         data,
         auto_approve_requests,
         turn_context,
         started_at_ms,
         last_activity_ms,
         turn_timeout_ms,
         stall_timeout_ms
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
          auto_approve_requests,
          turn_context,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
        )

      {:ok, payload} ->
        Messages.emit(
          on_message,
          :other_message,
          %{
            payload: payload,
            raw: payload_string
          },
          PortMetadata.message(@provider_kind, port, payload, turn_context)
        )

        receive_loop(
          port,
          on_message,
          "",
          auto_approve_requests,
          turn_context,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
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
            PortMetadata.message(@provider_kind, port, %{raw: payload_string}, turn_context)
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
          "",
          auto_approve_requests,
          turn_context,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
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
      PortMetadata.message(@provider_kind, port, payload, turn_context)
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
         auto_approve_requests,
         turn_context,
         started_at_ms,
         last_activity_ms,
         turn_timeout_ms,
         stall_timeout_ms
       ) do
    metadata = PortMetadata.message(@provider_kind, port, payload, turn_context)

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
          "",
          auto_approve_requests,
          turn_context,
          started_at_ms,
          last_activity_ms,
          turn_timeout_ms,
          stall_timeout_ms
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
          ObsLogger.emit(
            :debug,
            :codex_turn_notification,
            EventFields.turn(turn_context, %{
              operation: "codex_notification",
              result_summary: "method=#{method}",
              payload_summary: EventFields.stream_summary(payload)
            })
          )

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
            "",
            auto_approve_requests,
            turn_context,
            started_at_ms,
            last_activity_ms,
            turn_timeout_ms,
            stall_timeout_ms
          )
        end
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp receive_timeout_ms(now_ms, started_at_ms, last_activity_ms, turn_timeout_ms, stall_timeout_ms) do
    [
      remaining_timeout_ms(now_ms, started_at_ms, turn_timeout_ms),
      remaining_timeout_ms(now_ms, last_activity_ms, stall_timeout_ms)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> turn_timeout_ms end)
    |> max(0)
  end

  defp remaining_timeout_ms(now_ms, base_ms, timeout_ms)
       when is_integer(timeout_ms) and timeout_ms > 0 and is_integer(base_ms) do
    timeout_ms - max(now_ms - base_ms, 0)
  end

  defp remaining_timeout_ms(_now_ms, _base_ms, _timeout_ms), do: nil

  defp timeout_reason(now_ms, started_at_ms, last_activity_ms, turn_timeout_ms, stall_timeout_ms) do
    cond do
      timeout_expired?(now_ms, started_at_ms, turn_timeout_ms) -> :turn_timeout
      timeout_expired?(now_ms, last_activity_ms, stall_timeout_ms) -> :stall_timeout
      true -> nil
    end
  end

  defp timeout_expired?(now_ms, base_ms, timeout_ms)
       when is_integer(timeout_ms) and timeout_ms > 0 and is_integer(base_ms) do
    now_ms - base_ms >= timeout_ms
  end

  defp timeout_expired?(_now_ms, _base_ms, _timeout_ms), do: false

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
      PortMetadata.message(@provider_kind, port, %{raw: raw_payload}, turn_context)
    )
  end

  defp emit_non_json_stream_message(_on_message, _event, _raw_payload, _port, _turn_context), do: :ok
end
