defmodule SymphonyWorkerDaemon.Session.Ledger do
  @moduledoc false

  use GenServer

  alias SymphonyWorkerDaemon.Session.Filters
  alias SymphonyWorkerDaemon.Session.Ledger.{Health, Persistence, Summary}

  @type filters :: Filters.t()
  @type health :: Health.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec record_session(GenServer.server() | nil, map()) :: :ok
  def record_session(nil, _summary), do: :ok

  def record_session(server, summary) when is_map(summary) do
    safe_cast(server, {:record_session, summary})
  end

  @spec record_session_sync(GenServer.server() | nil, map()) :: :ok
  def record_session_sync(nil, _summary), do: :ok

  def record_session_sync(server, summary) when is_map(summary) do
    safe_call(server, {:record_session, summary}, :ok)
  end

  @spec mark_active_lost(GenServer.server() | nil, term()) :: :ok
  def mark_active_lost(nil, _reason), do: :ok

  def mark_active_lost(server, reason) do
    safe_call(server, {:mark_active_lost, reason}, :ok)
  end

  @spec mark_cleaned(GenServer.server() | nil, String.t()) :: :ok | {:error, :session_not_found}
  def mark_cleaned(nil, _session_id), do: {:error, :session_not_found}

  def mark_cleaned(server, session_id) when is_binary(session_id) do
    safe_call(server, {:mark_cleaned, session_id}, {:error, :session_not_found})
  end

  @spec get_session(GenServer.server() | nil, String.t()) :: {:ok, map()} | {:error, :session_not_found}
  def get_session(nil, _session_id), do: {:error, :session_not_found}

  def get_session(server, session_id) when is_binary(session_id) do
    safe_call(server, {:get_session, session_id}, {:error, :session_not_found})
  end

  @spec list_sessions(GenServer.server() | nil, filters()) :: {:ok, [map()]} | {:error, term()}
  def list_sessions(nil, _filters), do: {:ok, []}

  def list_sessions(server, filters) when is_map(filters) or is_list(filters) do
    safe_call(server, {:list_sessions, filters}, {:error, :session_ledger_unavailable})
  end

  @spec health(GenServer.server() | nil) :: health()
  def health(nil), do: Health.ready(nil)

  def health(server) do
    safe_call(server, :health, Health.unavailable())
  end

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) when is_list(opts) do
    path = opts |> Keyword.get(:path) |> Persistence.normalize_path()

    {sessions, health} =
      path
      |> Persistence.load()
      |> then(fn {sessions, health} -> {Summary.mark_active_lost(sessions, "daemon_restarted", now_ms()), health} end)

    state = %{path: path, sessions: sessions, health: health}

    if path && map_size(sessions) > 0 do
      {:ok, Persistence.persist(state)}
    else
      {:ok, state}
    end
  end

  @impl true
  @spec handle_cast(term(), map()) :: {:noreply, map()}
  def handle_cast({:record_session, summary}, state) do
    state
    |> put_session(summary)
    |> persist_and_continue()
  end

  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:mark_active_lost, reason}, _from, state) do
    state =
      state
      |> Map.update!(:sessions, &Summary.mark_active_lost(&1, reason, now_ms()))
      |> Persistence.persist()

    {:reply, :ok, state}
  end

  def handle_call({:record_session, summary}, _from, state) do
    state =
      state
      |> put_session(summary)
      |> Persistence.persist()

    {:reply, :ok, state}
  end

  def handle_call({:mark_cleaned, session_id}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, summary} ->
        state =
          state
          |> put_session(Summary.mark_cleaned(summary, now_ms()))
          |> Persistence.persist()

        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  def handle_call({:get_session, session_id}, _from, state) do
    {:reply, Summary.fetch(state.sessions, session_id), state}
  end

  def handle_call({:list_sessions, filters}, _from, state) do
    sessions =
      state.sessions
      |> Map.values()
      |> Enum.filter(&Filters.matches?(&1, filters))
      |> Enum.sort_by(&(Map.get(&1, "updated_at_ms") || Map.get(&1, "started_at_ms", 0)), :desc)

    {:reply, {:ok, sessions}, state}
  end

  def handle_call(:health, _from, state) do
    {:reply, Map.get(state, :health, Health.ready(Map.get(state, :path))), state}
  end

  defp put_session(state, summary) when is_map(summary) do
    sessions = Summary.put(state.sessions, summary)
    %{state | sessions: sessions}
  end

  defp persist_and_continue(state) do
    {:noreply, Persistence.persist(state)}
  end

  defp safe_call(server, message, default) do
    GenServer.call(server, message)
  catch
    :exit, _reason -> default
  end

  defp safe_cast(server, message) do
    GenServer.cast(server, message)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp now_ms, do: System.system_time(:millisecond)
end
