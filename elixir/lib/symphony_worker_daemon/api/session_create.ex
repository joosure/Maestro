defmodule SymphonyWorkerDaemon.Api.SessionCreate do
  @moduledoc false

  import SymphonyWorkerDaemon.Api.Response, only: [error_payload: 3, json: 3]

  alias SymphonyWorkerDaemon.Api.Audit
  alias SymphonyWorkerDaemon.Auth

  defguardp is_dynamic_tool_bridge_error(reason)
            when reason in [
                   :dynamic_tool_bridge_proxy_disabled,
                   :dynamic_tool_bridge_upstream_base_url_missing,
                   :dynamic_tool_bridge_upstream_base_url_invalid,
                   :dynamic_tool_bridge_upstream_token_missing,
                   :dynamic_tool_bridge_upstream_allowlist_missing
                 ] or
                   (is_tuple(reason) and tuple_size(reason) > 0 and
                      elem(reason, 0) in [
                        :dynamic_tool_bridge_upstream_not_allowlisted,
                        :dynamic_tool_bridge_upstream_address_blocked,
                        :dynamic_tool_bridge_upstream_address_unresolved,
                        :invalid_dynamic_tool_bridge_allowed_upstream
                      ])

  @spec error(Plug.Conn.t(), map(), map(), term()) :: Plug.Conn.t()
  def error(conn, _principal, _request, {:unsupported_protocol_version, _expected, _actual} = reason) do
    json(conn, 426, error_payload("unsupported_protocol_version", reason, false))
  end

  def error(conn, _principal, _request, {:unsupported_required_features, _missing} = reason) do
    json(conn, 422, error_payload("unsupported_required_features", reason, false))
  end

  def error(conn, _principal, _request, {:payload_too_large, _field, _size, _max_bytes} = reason) do
    json(conn, 413, error_payload("payload_too_large", reason, false))
  end

  def error(conn, _principal, _request, {:payload_invalid, _field} = reason) do
    json(conn, 422, error_payload("payload_invalid", reason, false))
  end

  def error(conn, _principal, _request, {:payload_unknown_fields, _field, _keys} = reason) do
    json(conn, 422, error_payload("payload_unknown_fields", reason, false))
  end

  def error(conn, principal, request, :session_forbidden) do
    Audit.emit(conn, principal, :worker_daemon_session_create_forbidden, Audit.request_fields(request))
    json(conn, 403, error_payload("session_forbidden", Auth.principal_summary(principal), false))
  end

  def error(conn, _principal, _request, {:command_not_allowlisted, _summary} = reason) do
    json(conn, 422, error_payload("command_rejected", reason, false))
  end

  def error(conn, _principal, _request, {:allowed_executable_unavailable, _command, _reason} = reason) do
    json(conn, 422, error_payload("command_rejected", reason, false))
  end

  def error(conn, _principal, _request, {:executable_path_unavailable, _path, _reason} = reason) do
    json(conn, 422, error_payload("command_rejected", reason, false))
  end

  def error(conn, _principal, _request, :worker_full) do
    json(conn, 429, error_payload("worker_full", :worker_full, true))
  end

  def error(conn, _principal, _request, :tenant_session_quota_exceeded) do
    json(conn, 429, error_payload("tenant_session_quota_exceeded", :tenant_session_quota_exceeded, true))
  end

  def error(conn, _principal, _request, :draining) do
    json(conn, 429, error_payload("worker_draining", :draining, true))
  end

  def error(conn, _principal, _request, :unavailable) do
    json(conn, 429, error_payload("worker_unavailable", :unavailable, true))
  end

  def error(conn, _principal, _request, {:session_conflict, _session_id} = reason) do
    json(conn, 409, error_payload("session_conflict", reason, false))
  end

  def error(conn, _principal, _request, reason) when is_dynamic_tool_bridge_error(reason) do
    json(conn, 422, error_payload("dynamic_tool_bridge_rejected", reason, false))
  end

  def error(conn, _principal, _request, reason) do
    json(conn, 422, error_payload("session_start_failed", reason, false))
  end
end
