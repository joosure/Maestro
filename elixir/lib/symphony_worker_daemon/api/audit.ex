defmodule SymphonyWorkerDaemon.Api.Audit do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @spec emit(Plug.Conn.t(), map(), atom(), map()) :: :ok
  def emit(conn, principal, event, fields) when is_map(principal) and is_atom(event) and is_map(fields) do
    ObsLogger.emit(:info, event, Map.merge(base_fields(conn, principal), fields))
    :ok
  end

  @spec rate_limited(Plug.Conn.t(), map(), atom(), tuple()) :: :ok
  def rate_limited(conn, principal, scope, {:rate_limited, retry_after_ms, limit, window_ms}) when is_map(principal) and is_atom(scope) do
    emit(conn, principal, :worker_daemon_request_rate_limited, %{
      scope: Atom.to_string(scope),
      retry_after_ms: retry_after_ms,
      limit: limit,
      window_ms: window_ms
    })
  end

  @spec request_fields(map(), map()) :: map()
  def request_fields(request, response \\ %{}) when is_map(request) and is_map(response) do
    caller = Map.get(request, "caller", %{})

    %{
      request_id: Map.get(request, "request_id"),
      session_id: Map.get(response, "session_id") || Map.get(request, "session_id"),
      run_id: Map.get(request, "run_id"),
      caller_owner: Map.get(caller, "owner"),
      caller_tenant_id: Map.get(caller, "tenant_id"),
      provider_kind: Map.get(caller, "provider_kind"),
      worker_pool: Map.get(caller, "worker_pool")
    }
    |> compact_map()
  end

  @spec remote_ip(term()) :: String.t() | nil
  def remote_ip(remote_ip) when is_tuple(remote_ip) do
    remote_ip
    |> :inet.ntoa()
    |> to_string()
  catch
    _kind, _reason -> nil
  end

  def remote_ip(_remote_ip), do: nil

  defp base_fields(conn, principal) do
    %{
      component: "symphony_worker_daemon",
      owner: Map.get(principal, :owner),
      tenant_id: Map.get(principal, :tenant_id),
      auth_mode: Map.get(principal, :auth_mode),
      request_method: conn.method,
      request_path: conn.request_path,
      remote_ip: remote_ip(conn.remote_ip)
    }
    |> compact_map()
  end

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
