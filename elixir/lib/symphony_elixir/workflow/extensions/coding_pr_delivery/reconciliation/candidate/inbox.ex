defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox do
  @moduledoc """
  Runtime inbox for provider-safe change-proposal reconciliation candidates.

  The inbox stores tracker issue ids supplied by safe runtime sources such as
  webhooks, provider watchers, or operator-triggered one-shot runs. Workflow
  configuration never stores concrete issue ids; the poll cycle drains this
  inbox only when reconciliation is enabled.
  """

  use GenServer

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox.{Error, Options}
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Lifecycle

  defmodule State do
    @moduledoc false

    defstruct queue: :queue.new(),
              queued_ids: MapSet.new(),
              queue_limit: nil,
              lifecycle: Lifecycle.new()
  end

  @type enqueue_result :: %{
          required(:accepted_count) => non_neg_integer(),
          required(:duplicate_count) => non_neg_integer(),
          required(:dropped_count) => non_neg_integer(),
          required(:invalid_count) => non_neg_integer(),
          required(:queued_count) => non_neg_integer(),
          optional(:reactivated_count) => non_neg_integer()
        }

  @type defer_result :: %{
          required(:accepted_count) => non_neg_integer(),
          required(:duplicate_count) => non_neg_integer(),
          required(:dropped_count) => non_neg_integer(),
          required(:invalid_count) => non_neg_integer(),
          required(:suspended_count) => non_neg_integer(),
          required(:queued_count) => non_neg_integer(),
          required(:deferred_count) => non_neg_integer(),
          required(:suspended_issue_ids) => [String.t()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    with {:ok, opts} <- Options.keyword_opts(opts, :start_link_options_not_keyword),
         {:ok, opts} <- Options.start_opts(opts) do
      case Keyword.fetch(opts, :name) do
        {:ok, nil} ->
          GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))

        {:ok, name} ->
          GenServer.start_link(__MODULE__, opts, name: name)

        :error ->
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
    end
  end

  @spec enqueue_issue_ids([term()], keyword()) :: {:ok, enqueue_result()} | {:error, term()}
  def enqueue_issue_ids(issue_ids, opts \\ []) do
    with {:ok, opts} <- Options.keyword_opts(opts, :options_not_keyword),
         {:ok, issue_ids, invalid_count} <- Options.issue_ids(issue_ids),
         {:ok, server} <- Options.server(opts, __MODULE__) do
      call_server(server, fn pid ->
        GenServer.call(pid, {:enqueue_issue_ids, issue_ids, invalid_count})
      end)
    end
  end

  @spec defer_issue_ids([term()], keyword()) :: {:ok, defer_result()} | {:error, term()}
  def defer_issue_ids(issue_ids, opts \\ []) do
    with {:ok, opts} <- Options.keyword_opts(opts, :options_not_keyword),
         {:ok, issue_ids, invalid_count} <- Options.issue_ids(issue_ids),
         {:ok, server} <- Options.server(opts, __MODULE__),
         {:ok, policy} <- Options.defer_policy(opts) do
      call_server(server, fn pid ->
        GenServer.call(pid, {:defer_issue_ids, issue_ids, invalid_count, policy})
      end)
    end
  end

  @spec reactivate_issue_ids([term()], keyword()) :: {:ok, enqueue_result()} | {:error, term()}
  def reactivate_issue_ids(issue_ids, opts \\ []), do: enqueue_issue_ids(issue_ids, opts)

  @spec lifecycle_snapshot(keyword()) :: map() | {:error, map()}
  def lifecycle_snapshot(opts \\ []) do
    with {:ok, opts} <- Options.keyword_opts(opts, :options_not_keyword),
         {:ok, server} <- Options.server(opts, __MODULE__) do
      call_server(server, fn pid -> GenServer.call(pid, :lifecycle_snapshot) end)
    end
  end

  @spec drain_issue_ids(keyword()) :: [String.t()] | {:error, map()}
  def drain_issue_ids(opts \\ []) do
    with {:ok, opts} <- Options.keyword_opts(opts, :options_not_keyword),
         {:ok, server} <- Options.server(opts, __MODULE__),
         {:ok, limit} <- Options.drain_limit(opts) do
      call_server(server, fn pid ->
        GenServer.call(pid, {:drain_issue_ids, limit})
      end)
    end
  end

  @impl true
  def init(opts) do
    with {:ok, opts} <- Options.start_opts(opts),
         {:ok, queue_limit} <- Options.queue_limit(opts) do
      {:ok, %State{queue_limit: queue_limit, lifecycle: Lifecycle.new(opts)}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:enqueue_issue_ids, issue_ids, invalid_count}, _from, %State{} = state) do
    {lifecycle, reactivated_count} = Lifecycle.reactivate(state.lifecycle, issue_ids)
    state = %{state | lifecycle: lifecycle}
    {state, result} = enqueue_all(state, issue_ids)
    result = Map.put(result, :invalid_count, invalid_count)
    result = Map.put(result, :reactivated_count, reactivated_count)
    {:reply, {:ok, result}, state}
  end

  def handle_call({:defer_issue_ids, issue_ids, invalid_count, policy}, _from, %State{} = state) do
    {state, result} = defer_all(state, issue_ids, policy)
    result = Map.put(result, :invalid_count, invalid_count)
    {:reply, {:ok, result}, state}
  end

  def handle_call(:lifecycle_snapshot, _from, %State{} = state) do
    {:reply, Lifecycle.snapshot(state.lifecycle), state}
  end

  def handle_call({:drain_issue_ids, limit}, _from, %State{} = state) do
    {issue_ids, state} = drain(state, limit, [])
    {:reply, Enum.reverse(issue_ids), state}
  end

  def handle_call(:reset, _from, %State{} = state) do
    {:reply, :ok, %State{queue_limit: state.queue_limit, lifecycle: Lifecycle.reset(state.lifecycle)}}
  end

  defp enqueue_all(%State{} = state, issue_ids) when is_list(issue_ids) do
    {state, accepted_count, duplicate_count, dropped_count} =
      Enum.reduce(issue_ids, {state, 0, 0, 0}, fn issue_id, {%State{} = state_acc, accepted, duplicates, dropped} ->
        cond do
          MapSet.member?(state_acc.queued_ids, issue_id) ->
            {state_acc, accepted, duplicates + 1, dropped}

          MapSet.size(state_acc.queued_ids) >= state_acc.queue_limit ->
            {state_acc, accepted, duplicates, dropped + 1}

          true ->
            state_acc = %{
              state_acc
              | queue: :queue.in(issue_id, state_acc.queue),
                queued_ids: MapSet.put(state_acc.queued_ids, issue_id)
            }

            {state_acc, accepted + 1, duplicates, dropped}
        end
      end)

    result = %{
      accepted_count: accepted_count,
      duplicate_count: duplicate_count,
      dropped_count: dropped_count,
      queued_count: MapSet.size(state.queued_ids)
    }

    {state, result}
  end

  defp defer_all(%State{} = state, issue_ids, policy) when is_list(issue_ids) and is_map(policy) do
    %{lifecycle: lifecycle, deferred_issue_ids: deferred_issue_ids, suspended_issue_ids: suspended_issue_ids} =
      Lifecycle.defer(state.lifecycle, issue_ids, policy)

    state = %{state | lifecycle: lifecycle}

    {state, accepted_count, duplicate_count, dropped_count} =
      enqueue_all_counted(state, deferred_issue_ids)

    result = %{
      accepted_count: accepted_count,
      duplicate_count: duplicate_count,
      dropped_count: dropped_count,
      suspended_count: length(suspended_issue_ids),
      queued_count: MapSet.size(state.queued_ids),
      deferred_count: Lifecycle.snapshot(state.lifecycle).deferred_count,
      suspended_issue_ids: suspended_issue_ids
    }

    {state, result}
  end

  defp enqueue_all_counted(%State{} = state, issue_ids) when is_list(issue_ids) do
    Enum.reduce(issue_ids, {state, 0, 0, 0}, fn issue_id, {state_acc, accepted, duplicates, dropped} ->
      enqueue_one(state_acc, issue_id, accepted, duplicates, dropped)
    end)
  end

  defp enqueue_one(%State{} = state, issue_id, accepted, duplicates, dropped) do
    cond do
      MapSet.member?(state.queued_ids, issue_id) ->
        {state, accepted, duplicates + 1, dropped}

      MapSet.size(state.queued_ids) >= state.queue_limit ->
        {state, accepted, duplicates, dropped + 1}

      true ->
        state = %{
          state
          | queue: :queue.in(issue_id, state.queue),
            queued_ids: MapSet.put(state.queued_ids, issue_id)
        }

        {state, accepted + 1, duplicates, dropped}
    end
  end

  defp drain(%State{} = state, limit, acc) when limit <= 0, do: {acc, state}

  defp drain(%State{} = state, limit, acc) do
    case :queue.out(state.queue) do
      {{:value, issue_id}, queue} ->
        state = %{state | queue: queue, queued_ids: MapSet.delete(state.queued_ids, issue_id)}
        drain(state, limit - 1, [issue_id | acc])

      {:empty, _queue} ->
        {acc, state}
    end
  end

  defp call_server(server, fun) when is_atom(server) and is_function(fun, 1) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> fun.(pid)
      _other -> {:error, Error.unavailable(server)}
    end
  end

  defp call_server(server, fun) when is_pid(server) and is_function(fun, 1), do: fun.(server)
end
