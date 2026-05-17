defmodule SymphonyWorkerDaemon.Api.Response do
  @moduledoc false

  import Plug.Conn, only: [put_resp_content_type: 2, send_resp: 3]

  alias SymphonyElixir.Observability.Redaction
  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields

  @code_key ProtocolFields.code()
  @message_key ProtocolFields.message()
  @retryable_key ProtocolFields.retryable()
  @details_key ProtocolFields.details()

  @spec json(Plug.Conn.t(), Plug.Conn.status(), term()) :: Plug.Conn.t()
  def json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  @spec error_payload(String.t(), term(), boolean()) :: map()
  def error_payload(code, details, retryable?) do
    %{
      @code_key => code,
      @message_key => code,
      @retryable_key => retryable?,
      @details_key => safe_details(details)
    }
  end

  @spec mutation_error(Plug.Conn.t(), String.t(), term(), String.t(), boolean()) :: Plug.Conn.t()
  def mutation_error(conn, _session_id, {:unsupported_protocol_version, _expected, _actual} = reason, _code, _retryable?) do
    json(conn, 426, error_payload("unsupported_protocol_version", reason, false))
  end

  def mutation_error(conn, _session_id, {:payload_too_large, _field, _size, _max_bytes} = reason, _code, _retryable?) do
    json(conn, 413, error_payload("payload_too_large", reason, false))
  end

  def mutation_error(conn, _session_id, {:payload_invalid, _field} = reason, _code, _retryable?) do
    json(conn, 422, error_payload("payload_invalid", reason, false))
  end

  def mutation_error(conn, _session_id, {:payload_unknown_fields, _field, _keys} = reason, _code, _retryable?) do
    json(conn, 422, error_payload("payload_unknown_fields", reason, false))
  end

  def mutation_error(conn, _session_id, reason, _code, _retryable?)
      when reason in [
             :protocol_version_missing,
             :request_id_missing,
             :idempotency_key_missing,
             :worker_daemon_input_request_invalid,
             :worker_daemon_stop_request_invalid,
             :worker_daemon_cleanup_request_invalid
           ] do
    json(conn, 422, error_payload(Atom.to_string(reason), reason, false))
  end

  def mutation_error(conn, session_id, :session_not_found, _code, _retryable?) do
    json(conn, 404, error_payload("session_not_found", session_id, false))
  end

  def mutation_error(conn, session_id, :session_forbidden, _code, _retryable?) do
    json(conn, 403, error_payload("session_forbidden", session_id, false))
  end

  def mutation_error(conn, _session_id, reason, code, retryable?) do
    json(conn, 409, error_payload(code, reason, retryable?))
  end

  @spec stringify_map(map()) :: map()
  def stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp safe_details(details) when is_binary(details), do: Redaction.redact_string(details)
  defp safe_details(details) when is_atom(details), do: Atom.to_string(details)
  defp safe_details(details), do: Redaction.summarize(details, 512)

  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
