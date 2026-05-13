defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.Session do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.{Connection, Filters, Transport}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.SessionHandle
  alias SymphonyWorkerDaemon.Protocol

  @spec list_sessions(Target.t(), keyword()) :: {:ok, [Protocol.session_summary()]} | {:error, term()}
  def list_sessions(%Target{} = target, opts \\ []) do
    with {:ok, endpoint} <- Connection.endpoint(target, opts),
         token <- Connection.token(opts),
         filters <- Filters.session_filters(target, opts),
         {:ok, payload} <- Transport.request(:get, endpoint, Protocol.sessions_path(filters), token, nil, opts) do
      Protocol.normalize_session_list_response(payload)
    end
  end

  @spec send_input(SessionHandle.t(), iodata(), keyword()) :: :ok | {:error, term()}
  def send_input(%SessionHandle{} = handle, data, opts \\ []) do
    request = Protocol.input_request(data, opts)

    case Transport.request(:post, handle.endpoint, Protocol.input_path(handle.session_id), handle.token, request, opts) do
      {:ok, _payload} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec stop_session(SessionHandle.t(), keyword()) :: :ok | {:error, term()}
  def stop_session(%SessionHandle{} = handle, opts \\ []) do
    request = Protocol.stop_request(opts)

    case Transport.request(:post, handle.endpoint, Protocol.stop_path(handle.session_id), handle.token, request, opts) do
      {:ok, _payload} -> :ok
      {:error, {:worker_daemon_error, :post, 404, _code, _payload}} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec cleanup_session(SessionHandle.t(), keyword()) :: :ok | {:error, term()}
  def cleanup_session(%SessionHandle{} = handle, opts \\ []) do
    request = Protocol.cleanup_request(opts)

    case Transport.request(:post, handle.endpoint, Protocol.cleanup_path(handle.session_id), handle.token, request, opts) do
      {:ok, _payload} -> :ok
      {:error, {:worker_daemon_error, :post, 404, _code, _payload}} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec session_status(SessionHandle.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def session_status(%SessionHandle{} = handle, opts \\ []) do
    with {:ok, payload} <- Transport.request(:get, handle.endpoint, Protocol.session_path(handle.session_id), handle.token, nil, opts),
         {:ok, status} <- Protocol.normalize_status(payload) do
      {:ok, status}
    end
  end

  @spec session_events(SessionHandle.t(), keyword()) :: {:ok, [Protocol.session_event()]} | {:error, term()}
  def session_events(%SessionHandle{} = handle, opts \\ []) do
    with {:ok, payload} <-
           Transport.request(:get, handle.endpoint, Protocol.events_path(handle.session_id, Filters.session_event_filters(opts)), handle.token, nil, opts) do
      Protocol.normalize_session_events_response(payload)
    end
  end
end
