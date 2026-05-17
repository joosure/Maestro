defmodule SymphonyWorkerDaemon.Api.SessionAccess do
  @moduledoc false

  alias SymphonyWorkerDaemon.Auth
  alias SymphonyWorkerDaemon.Auth.Defaults, as: AuthDefaults
  alias SymphonyWorkerDaemon.Session

  @spec lookup_authorized_session(Plug.Conn.t(), String.t()) :: {:ok, pid()} | {:error, :session_not_found | :session_forbidden}
  def lookup_authorized_session(conn, session_id) do
    with {:ok, pid} <- lookup_session(conn, session_id),
         :ok <- authorize_session(conn, pid) do
      {:ok, pid}
    end
  end

  @spec lookup_authorized_status(Plug.Conn.t(), String.t()) :: {:ok, map()} | {:error, :session_not_found | :session_forbidden}
  def lookup_authorized_status(conn, session_id) do
    case lookup_authorized_session(conn, session_id) do
      {:ok, pid} ->
        {:ok, Session.Server.status(pid)}

      {:error, :session_not_found} ->
        lookup_authorized_ledger_session(conn, session_id)

      {:error, _reason} = error ->
        error
    end
  end

  @spec lookup_authorized_ledger_session(Plug.Conn.t(), String.t()) :: {:ok, map()} | {:error, :session_not_found | :session_forbidden}
  def lookup_authorized_ledger_session(conn, session_id) do
    with {:ok, summary} <- Session.Ledger.get_session(session_ledger(conn), session_id),
         :ok <- Auth.authorize_session(principal(conn), summary) do
      {:ok, summary}
    end
  end

  @spec session_ledger(Plug.Conn.t()) :: pid() | atom() | nil
  def session_ledger(conn), do: conn |> runtime_opts() |> Keyword.get(:session_ledger)

  @spec session_list_opts(Plug.Conn.t()) :: keyword()
  def session_list_opts(conn), do: [session_ledger: session_ledger(conn)]

  defp lookup_session(conn, session_id) do
    conn
    |> runtime_opts()
    |> Keyword.get(:registry, SymphonyWorkerDaemon.SessionRegistry)
    |> Session.Supervisor.lookup(session_id)
  rescue
    ArgumentError -> {:error, :session_not_found}
  catch
    :exit, _reason -> {:error, :session_not_found}
  end

  defp authorize_session(conn, pid) when is_pid(pid) do
    Auth.authorize_session(principal(conn), Session.Server.summary(pid))
  end

  defp runtime_opts(conn), do: conn.assigns[:worker_daemon_opts] || []

  defp principal(conn), do: conn.assigns[:worker_daemon_principal] || AuthDefaults.default_principal()
end
