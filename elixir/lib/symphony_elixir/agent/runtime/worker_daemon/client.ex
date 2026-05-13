defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.{Connection, Health, Session, SessionCreate, Transport}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.SessionHandle
  alias SymphonyWorkerDaemon.Protocol

  @type requester :: Transport.requester()
  @type request_result :: Transport.request_result()

  @spec create_session(CommandSpec.t(), Target.t(), keyword()) :: {:ok, SessionHandle.t()} | {:error, term()}
  defdelegate create_session(command_spec, target, opts \\ []), to: SessionCreate

  @spec health(Target.t(), keyword()) :: {:ok, Protocol.health_response()} | {:error, term()}
  defdelegate health(target, opts \\ []), to: Health

  @spec preflight(Target.t(), keyword()) :: {:ok, Protocol.health_response()} | {:error, term()}
  defdelegate preflight(target, opts \\ []), to: Health

  @spec validate_health(Target.t(), Protocol.health_response(), keyword()) :: :ok | {:error, term()}
  defdelegate validate_health(target, health, opts \\ []), to: Health

  @spec list_sessions(Target.t(), keyword()) :: {:ok, [Protocol.session_summary()]} | {:error, term()}
  defdelegate list_sessions(target, opts \\ []), to: Session

  @spec send_input(SessionHandle.t(), iodata(), keyword()) :: :ok | {:error, term()}
  defdelegate send_input(handle, data, opts \\ []), to: Session

  @spec stop_session(SessionHandle.t(), keyword()) :: :ok | {:error, term()}
  defdelegate stop_session(handle, opts \\ []), to: Session

  @spec cleanup_session(SessionHandle.t(), keyword()) :: :ok | {:error, term()}
  defdelegate cleanup_session(handle, opts \\ []), to: Session

  @spec session_status(SessionHandle.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defdelegate session_status(handle, opts \\ []), to: Session

  @spec session_events(SessionHandle.t(), keyword()) :: {:ok, [Protocol.session_event()]} | {:error, term()}
  defdelegate session_events(handle, opts \\ []), to: Session

  @spec endpoint(Target.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defdelegate endpoint(target, opts \\ []), to: Connection

  @spec token(keyword()) :: String.t() | nil
  defdelegate token(opts \\ []), to: Connection

  @spec request(atom(), String.t(), String.t(), String.t() | nil, map() | nil, keyword()) :: request_result()
  defdelegate request(method, endpoint, path, token, body, opts), to: Transport

  @spec default_requester(atom(), String.t(), [{String.t(), String.t()}], map() | nil, map()) ::
          {:ok, pos_integer(), term()} | {:error, term()}
  defdelegate default_requester(method, url, headers, body, request_opts), to: Transport
end
