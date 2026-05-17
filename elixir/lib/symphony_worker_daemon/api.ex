defmodule SymphonyWorkerDaemon.Api do
  @moduledoc false

  use Plug.Router

  import SymphonyWorkerDaemon.Api.Response, only: [error_payload: 3, json: 3, mutation_error: 5]

  alias SymphonyElixir.LegalSourceInfo

  alias SymphonyWorkerDaemon.Api.{
    Audit,
    Health,
    RateLimit,
    RequestLimits,
    RequestParams,
    SessionAccess,
    SessionCleanup,
    SessionCreate,
    SessionOptions
  }

  alias SymphonyWorkerDaemon.{Auth, Protocol}
  alias SymphonyWorkerDaemon.Auth.Defaults, as: AuthDefaults
  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields
  alias SymphonyWorkerDaemon.Protocol.Paths
  alias SymphonyWorkerDaemon.Protocol.ResponseStatus
  alias SymphonyWorkerDaemon.Session
  alias SymphonyWorkerDaemon.Session.Status

  @base_path Paths.base_path()
  @source_path Paths.source_path()
  @input_key ProtocolFields.input()
  @request_id_key ProtocolFields.request_id()
  @reason_key ProtocolFields.reason()
  @sessions_key ProtocolFields.sessions()
  @events_key ProtocolFields.events()
  @status_key ProtocolFields.status()

  plug(:match)
  plug(:reject_oversized_headers)
  plug(:reject_oversized_content_length)
  plug(:authenticate)
  plug(:throttle_authenticated)
  plug(:parse_body)
  plug(:dispatch)

  get @base_path <> "/health" do
    json(conn, 200, conn |> runtime_opts() |> Health.payload())
  end

  get @source_path do
    json(conn, 200, LegalSourceInfo.payload(notice_path: @source_path))
  end

  post @base_path <> "/sessions" do
    opts = runtime_opts(conn)
    request = RequestParams.body_params(conn)
    principal = principal(conn)
    features = Health.features(opts)

    with :ok <-
           Protocol.validate_create_request(
             request,
             features,
             RequestParams.protocol_limit_opts(opts)
           ),
         :ok <- Auth.authorize_create(principal, request),
         {:ok, _pid, payload} <-
           Session.Supervisor.start_session(
             Keyword.get(opts, :session_supervisor, Session.Supervisor),
             request,
             SessionOptions.build(opts)
           ) do
      Audit.emit(
        conn,
        principal,
        :worker_daemon_session_create_accepted,
        Audit.request_fields(request, payload)
      )

      json(conn, 201, payload)
    else
      {:error, reason} ->
        SessionCreate.error(conn, principal, request, reason)
    end
  end

  get @base_path <> "/sessions" do
    conn = fetch_query_params(conn)

    with {:ok, filters} <-
           Auth.authorize_filters(
             principal(conn),
             RequestParams.session_filters(conn.query_params)
           ),
         {:ok, sessions} <-
           conn
           |> runtime_opts()
           |> Keyword.get(:registry, SymphonyWorkerDaemon.SessionRegistry)
           |> Session.Supervisor.list_sessions(filters, SessionAccess.session_list_opts(conn)) do
      json(conn, 200, %{@sessions_key => sessions})
    else
      {:error, :session_forbidden} ->
        json(
          conn,
          403,
          error_payload("session_forbidden", Auth.principal_summary(principal(conn)), false)
        )
    end
  end

  get @base_path <> "/sessions/:session_id/events" do
    conn = fetch_query_params(conn)

    case SessionAccess.lookup_authorized_session(conn, session_id) do
      {:ok, pid} ->
        json(conn, 200, %{
          @events_key => Session.Server.events(pid, RequestParams.event_filters(conn.query_params))
        })

      {:error, :session_not_found} ->
        json(conn, 404, error_payload("session_not_found", session_id, false))

      {:error, :session_forbidden} ->
        json(conn, 403, error_payload("session_forbidden", session_id, false))
    end
  end

  get @base_path <> "/sessions/:session_id" do
    case SessionAccess.lookup_authorized_status(conn, session_id) do
      {:ok, status} ->
        json(conn, 200, status)

      {:error, :session_not_found} ->
        json(conn, 404, error_payload("session_not_found", session_id, false))

      {:error, :session_forbidden} ->
        json(conn, 403, error_payload("session_forbidden", session_id, false))
    end
  end

  post @base_path <> "/sessions/:session_id/input" do
    request = RequestParams.body_params(conn)

    with :ok <-
           Protocol.validate_input_request(
             request,
             RequestParams.protocol_limit_opts(runtime_opts(conn))
           ),
         {:ok, pid} <- SessionAccess.lookup_authorized_session(conn, session_id),
         :ok <- Session.Server.send_input(pid, Map.get(request, @input_key, "")) do
      Audit.emit(conn, principal(conn), :worker_daemon_session_input_accepted, %{
        session_id: session_id,
        request_id: Map.get(request, @request_id_key),
        input_bytes: byte_size(Map.get(request, @input_key, ""))
      })

      json(conn, 200, %{@status_key => ResponseStatus.accepted()})
    else
      {:error, reason} -> mutation_error(conn, session_id, reason, "session_input_failed", true)
    end
  end

  post @base_path <> "/sessions/:session_id/stop" do
    request = RequestParams.body_params(conn)

    with :ok <-
           Protocol.validate_stop_request(
             request,
             RequestParams.protocol_limit_opts(runtime_opts(conn))
           ),
         {:ok, pid} <- SessionAccess.lookup_authorized_session(conn, session_id) do
      :ok = Session.Server.stop_session(pid, reason: Map.get(request, @reason_key))

      Audit.emit(conn, principal(conn), :worker_daemon_session_stop_accepted, %{
        session_id: session_id,
        request_id: Map.get(request, @request_id_key),
        reason: Map.get(request, @reason_key)
      })

      json(conn, 200, %{@status_key => Status.stopped()})
    else
      {:error, reason} -> mutation_error(conn, session_id, reason, "session_stop_failed", true)
    end
  end

  post @base_path <> "/sessions/:session_id/cleanup" do
    request = RequestParams.body_params(conn)

    case Protocol.validate_cleanup_request(
           request,
           RequestParams.protocol_limit_opts(runtime_opts(conn))
         ) do
      :ok ->
        case SessionAccess.lookup_authorized_session(conn, session_id) do
          {:ok, pid} ->
            :ok = Session.Server.cleanup(pid, delete_workspace?: false)

            Audit.emit(conn, principal(conn), :worker_daemon_session_cleanup_accepted, %{
              session_id: session_id,
              request_id: Map.get(request, @request_id_key)
            })

            json(conn, 200, %{@status_key => Status.cleaned()})

          {:error, :session_not_found} ->
            SessionCleanup.cleanup_ledger_session(conn, session_id, request)

          {:error, :session_forbidden} ->
            json(conn, 403, error_payload("session_forbidden", session_id, false))
        end

      {:error, reason} ->
        mutation_error(conn, session_id, reason, "session_cleanup_failed", true)
    end
  end

  match _ do
    json(conn, 404, error_payload("not_found", conn.request_path, false))
  end

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> Plug.Conn.assign(:worker_daemon_opts, opts)
    |> super(opts)
  end

  @spec parse_body(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def parse_body(conn, _opts) do
    Plug.Parsers.call(conn, Plug.Parsers.init(RequestLimits.parser_options()))
  end

  @spec authenticate(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def authenticate(conn, _opts) do
    case Auth.authenticate(get_req_header(conn, "authorization"), runtime_opts(conn)) do
      {:ok, principal} ->
        Plug.Conn.assign(conn, :worker_daemon_principal, principal)

      {:error, :auth_failed} ->
        RateLimit.reject_auth_failed(conn)
    end
  end

  @spec throttle_authenticated(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def throttle_authenticated(conn, _opts) do
    RateLimit.throttle_authenticated(conn, session_create_path: @base_path <> "/sessions")
  end

  @spec reject_oversized_headers(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def reject_oversized_headers(conn, _opts) do
    RequestLimits.reject_oversized_headers(conn)
  end

  @spec reject_oversized_content_length(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def reject_oversized_content_length(conn, _opts) do
    RequestLimits.reject_oversized_content_length(conn)
  end

  defp runtime_opts(conn), do: conn.assigns[:worker_daemon_opts] || []

  defp principal(conn),
    do: conn.assigns[:worker_daemon_principal] || AuthDefaults.default_principal()
end
