defmodule SymphonyElixir.Observability.EventStore do
  @moduledoc """
  Keeps a bounded in-memory projection of structured observability events.

  This store is intentionally driven only by canonical events emitted through
  `SymphonyElixir.Observability.Logger.emit/3`. Low-value text logs remain file
  and console concerns and do not enter the query model.
  """

  use GenServer

  alias SymphonyElixir.Observability.EventStore.{
    Config,
    InputNormalizer,
    PendingQueue,
    Query,
    State
  }

  @default_recent_issue_limit 20
  @default_session_log_limit 200

  @type context :: %{
          optional(:issue_id) => String.t() | nil,
          optional(:issue_identifier) => String.t() | nil,
          optional(:run_id) => String.t() | nil,
          optional(:session_id) => String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @spec record(map()) :: :ok
  def record(event) when is_map(event) do
    cast_if_available({:record, InputNormalizer.event(event)})
  end

  @spec recent_events(keyword()) :: [map()]
  def recent_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_recent_issue_limit)
    call_if_available({:recent_events, limit}, [])
  end

  @spec recent_issue_events(context(), keyword()) :: [map()]
  def recent_issue_events(context, opts \\ []) when is_map(context) do
    limit = Keyword.get(opts, :limit, @default_recent_issue_limit)
    call_if_available({:recent_issue_events, InputNormalizer.context(context), limit}, [])
  end

  @spec agent_session_logs(context(), keyword()) :: [map()]
  def agent_session_logs(context, opts \\ []) when is_map(context) do
    limit = Keyword.get(opts, :limit, @default_session_log_limit)
    call_if_available({:agent_session_logs, InputNormalizer.context(context), limit}, [])
  end

  @spec dynamic_tool_usage_metrics(keyword()) :: map()
  def dynamic_tool_usage_metrics(opts \\ []) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 1_000)
    context = opts |> Keyword.get(:context, %{}) |> InputNormalizer.context()
    call_if_available({:dynamic_tool_usage_metrics, context, limit}, Query.empty_dynamic_tool_usage_metrics())
  end

  @spec configure_from_observability(map() | struct()) :: :ok
  def configure_from_observability(observability) do
    config = Config.normalize(observability)
    PendingQueue.set_limit(config.pending_event_queue_limit)
    call_if_available({:configure, config}, :ok)
  end

  @spec reset() :: :ok
  def reset do
    call_if_available(:reset, :ok)
  end

  @impl true
  def init(:ok) do
    config = Config.default()
    PendingQueue.initialize(config.pending_event_queue_limit)
    {:ok, State.new(config)}
  end

  @impl true
  def handle_call({:recent_events, limit}, _from, state) do
    {:reply, Query.recent_events(state, limit), state}
  end

  def handle_call({:recent_issue_events, context, limit}, _from, state) do
    {:reply, Query.recent_issue_events(state, context, limit), state}
  end

  def handle_call({:agent_session_logs, context, limit}, _from, state) do
    {:reply, Query.agent_session_logs(state, context, limit), state}
  end

  def handle_call({:dynamic_tool_usage_metrics, context, limit}, _from, state) do
    {:reply, Query.dynamic_tool_usage_metrics(state, context, limit), state}
  end

  def handle_call(:reset, _from, _state) do
    config = Config.default()
    PendingQueue.set_limit(config.pending_event_queue_limit)
    {:reply, :ok, State.new(config)}
  end

  def handle_call({:configure, config}, _from, state) do
    {:reply, :ok, State.reconfigure(state, config)}
  end

  @impl true
  def handle_cast({:record, event}, state) do
    PendingQueue.release_slot()
    {:noreply, State.append_event(state, event)}
  end

  defp call_if_available(message, default_reply) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        try do
          GenServer.call(__MODULE__, message, 5_000)
        catch
          :exit, _reason -> default_reply
        end

      _ ->
        default_reply
    end
  end

  defp cast_if_available(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        if PendingQueue.reserve_slot() do
          GenServer.cast(pid, message)
        end

        :ok

      _ ->
        :ok
    end
  end
end
