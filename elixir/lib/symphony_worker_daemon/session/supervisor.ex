defmodule SymphonyWorkerDaemon.Session.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields
  alias SymphonyWorkerDaemon.Session.{Filters, Ledger, Server}

  @session_id_key ProtocolFields.session_id()
  @request_id_key ProtocolFields.request_id()
  @worker_id_key ProtocolFields.worker_id()
  @daemon_instance_id_key ProtocolFields.daemon_instance_id()
  @lease_id_key ProtocolFields.lease_id()
  @status_key ProtocolFields.status()
  @metadata_key ProtocolFields.metadata()
  @run_id_key ProtocolFields.run_id()
  @cwd_key ProtocolFields.cwd()

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec start_session(map()) :: {:ok, pid(), map()} | {:error, term()}
  def start_session(request) when is_map(request), do: start_session(__MODULE__, request, [])

  @spec start_session(map(), keyword()) :: {:ok, pid(), map()} | {:error, term()}
  def start_session(request, opts) when is_map(request) and is_list(opts), do: start_session(__MODULE__, request, opts)

  @spec start_session(Supervisor.supervisor(), map(), keyword()) ::
          {:ok, pid(), map()} | {:error, term()}
  def start_session(supervisor, request, opts) when is_map(request) and is_list(opts) do
    session_id = session_id(request)

    child_opts =
      opts
      |> Keyword.put(:request, request)
      |> Keyword.put(:session_id, session_id)

    case DynamicSupervisor.start_child(supervisor, {Server, child_opts}) do
      {:ok, pid} ->
        {:ok, pid, response_payload(pid, request, session_id, opts)}

      {:error, {:already_started, pid}} ->
        if request_matches?(pid, request) do
          {:ok, pid, response_payload(pid, request, session_id, opts)}
        else
          {:error, {:session_conflict, session_id}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :session_not_found}
  def lookup(session_id) when is_binary(session_id), do: lookup(SymphonyWorkerDaemon.SessionRegistry, session_id)

  @spec lookup(module(), String.t()) :: {:ok, pid()} | {:error, :session_not_found}
  def lookup(registry, session_id) when is_binary(session_id) do
    Server.lookup(registry, session_id)
  end

  @spec list_sessions() :: {:ok, [map()]} | {:error, term()}
  def list_sessions, do: list_sessions(SymphonyWorkerDaemon.SessionRegistry, %{})

  @spec list_sessions(map() | keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_sessions(filters) when is_map(filters) or is_list(filters), do: list_sessions(SymphonyWorkerDaemon.SessionRegistry, filters)

  @spec list_sessions(module(), map() | keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_sessions(registry, filters) when is_map(filters) or is_list(filters), do: list_sessions(registry, filters, [])

  @spec list_sessions(module(), map() | keyword(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_sessions(registry, filters, opts) when (is_map(filters) or is_list(filters)) and is_list(opts) do
    live_sessions = live_sessions(registry, filters)

    ledger_sessions =
      opts
      |> Keyword.get(:session_ledger)
      |> Ledger.list_sessions(filters)
      |> case do
        {:ok, sessions} -> sessions
        {:error, _reason} -> []
      end

    sessions =
      ledger_sessions
      |> Kernel.++(live_sessions)
      |> Map.new(fn summary -> {Map.get(summary, @session_id_key), summary} end)
      |> Map.values()
      |> Enum.sort_by(&(Map.get(&1, ProtocolFields.updated_at_ms()) || Map.get(&1, ProtocolFields.started_at_ms(), 0)), :desc)

    {:ok, sessions}
  end

  defp live_sessions(registry, filters) do
    registry
    |> session_pids()
    |> Enum.flat_map(&safe_summary/1)
    |> Enum.filter(&Filters.matches?(&1, filters))
  rescue
    ArgumentError -> []
  catch
    :exit, _reason -> []
  end

  @impl true
  @spec init(keyword()) :: {:ok, term()}
  def init(opts) do
    opts
    |> Keyword.get(:session_ledger)
    |> Ledger.mark_active_lost(:session_supervisor_restarted)

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp session_id(%{@session_id_key => session_id}) when is_binary(session_id) and session_id != "", do: session_id
  defp session_id(%{@request_id_key => request_id}) when is_binary(request_id) and request_id != "", do: "session-" <> request_id
  defp session_id(_request), do: Ecto.UUID.generate()

  defp request_matches?(pid, request) when is_pid(pid) and is_map(request) do
    Server.request_matches?(pid, request)
  catch
    :exit, _reason -> false
  end

  defp response_payload(pid, request, session_id, opts) do
    status = Server.status(pid)

    %{
      @session_id_key => session_id,
      @worker_id_key => Keyword.get(opts, :worker_id),
      @daemon_instance_id_key => Keyword.get(opts, :daemon_instance_id),
      @lease_id_key => Map.get(status, @lease_id_key),
      @status_key => Map.get(status, @status_key),
      @metadata_key => %{
        @run_id_key => Map.get(request, @run_id_key),
        @cwd_key => Map.get(status, @cwd_key)
      }
    }
    |> compact_map()
  end

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp session_pids(registry) do
    Registry.select(registry, [{{:"$1", :"$2", :"$3"}, [], [:"$2"]}])
  end

  defp safe_summary(pid) when is_pid(pid) do
    [Server.summary(pid)]
  catch
    :exit, _reason -> []
  end
end
