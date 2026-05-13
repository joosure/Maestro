defmodule SymphonyWorkerDaemon.Api.SessionCleanup do
  @moduledoc false

  import SymphonyWorkerDaemon.Api.Response, only: [error_payload: 3, json: 3]

  alias SymphonyWorkerDaemon.Api.{Audit, SessionAccess}
  alias SymphonyWorkerDaemon.Session

  @spec cleanup_ledger_session(Plug.Conn.t(), String.t(), map()) :: Plug.Conn.t()
  def cleanup_ledger_session(conn, session_id, request) when is_binary(session_id) and is_map(request) do
    with {:ok, _summary} <- SessionAccess.lookup_authorized_ledger_session(conn, session_id),
         :ok <- Session.Ledger.mark_cleaned(SessionAccess.session_ledger(conn), session_id) do
      Audit.emit(conn, principal(conn), :worker_daemon_session_cleanup_accepted, %{
        session_id: session_id,
        request_id: Map.get(request, "request_id"),
        source: "session_ledger"
      })

      json(conn, 200, %{"status" => "cleaned"})
    else
      {:error, :session_not_found} -> json(conn, 404, error_payload("session_not_found", session_id, false))
      {:error, :session_forbidden} -> json(conn, 403, error_payload("session_forbidden", session_id, false))
    end
  end

  defp principal(conn), do: conn.assigns[:worker_daemon_principal] || %{owner: "symphony", roles: ["admin"]}
end
