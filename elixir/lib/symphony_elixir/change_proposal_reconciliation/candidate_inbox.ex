defmodule SymphonyElixir.ChangeProposalReconciliation.CandidateInbox do
  @moduledoc """
  Runtime inbox for provider-safe change-proposal reconciliation candidates.

  The inbox stores tracker issue ids supplied by safe runtime sources such as
  webhooks, provider watchers, or operator-triggered one-shot runs. Workflow
  configuration never stores concrete issue ids; the poll cycle drains this
  inbox only when reconciliation is enabled.
  """

  use GenServer

  @default_queue_limit 1_000
  @default_drain_limit 100

  defmodule State do
    @moduledoc false

    defstruct queue: :queue.new(),
              queued_ids: MapSet.new(),
              queue_limit: nil
  end

  @type enqueue_result :: %{
          accepted_count: non_neg_integer(),
          duplicate_count: non_neg_integer(),
          dropped_count: non_neg_integer(),
          queued_count: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} ->
        GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))

      {:ok, name} ->
        GenServer.start_link(__MODULE__, opts, name: name)

      :error ->
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @spec enqueue_issue_ids([term()], keyword()) :: {:ok, enqueue_result()} | {:error, term()}
  def enqueue_issue_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts) do
    issue_ids = normalize_issue_ids(issue_ids)
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, {:error, :candidate_inbox_unavailable}, fn ->
      GenServer.call(server, {:enqueue_issue_ids, issue_ids})
    end)
  end

  @spec drain_issue_ids(keyword() | pos_integer()) :: [String.t()]
  def drain_issue_ids(opts_or_limit \\ [])

  def drain_issue_ids(limit) when is_integer(limit) do
    drain_issue_ids(limit: limit)
  end

  def drain_issue_ids(opts) when is_list(opts) do
    limit = positive_integer(Keyword.get(opts, :limit), @default_drain_limit)
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, [], fn ->
      GenServer.call(server, {:drain_issue_ids, limit})
    end)
  end

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) when is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, :ok, fn ->
      GenServer.call(server, :reset)
    end)
  end

  @impl true
  def init(opts) do
    queue_limit = positive_integer(Keyword.get(opts, :queue_limit), @default_queue_limit)
    {:ok, %State{queue_limit: queue_limit}}
  end

  @impl true
  def handle_call({:enqueue_issue_ids, issue_ids}, _from, %State{} = state) do
    {state, result} = enqueue_all(state, issue_ids)
    {:reply, {:ok, result}, state}
  end

  def handle_call({:drain_issue_ids, limit}, _from, %State{} = state) do
    {issue_ids, state} = drain(state, limit, [])
    {:reply, Enum.reverse(issue_ids), state}
  end

  def handle_call(:reset, _from, %State{} = state) do
    {:reply, :ok, %State{queue_limit: state.queue_limit}}
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

  defp normalize_issue_ids(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> []
          trimmed -> [trimmed]
        end

      _value ->
        []
    end)
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp with_server(server, fallback, fun) when is_atom(server) and is_function(fun, 0) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> fun.()
      _other -> fallback
    end
  end

  defp with_server(server, _fallback, fun) when is_pid(server) and is_function(fun, 0), do: fun.()
  defp with_server(_server, fallback, _fun), do: fallback
end
