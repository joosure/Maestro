defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.EventStream do
  @moduledoc false

  use GenServer, restart: :temporary

  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.SessionHandle
  alias SymphonyWorkerDaemon.Protocol
  alias SymphonyWorkerDaemon.Session.Status

  @default_poll_interval_ms 50
  @default_event_limit 100

  @type start_opts :: [
          handle: SessionHandle.t(),
          owner: pid(),
          opts: keyword()
        ]

  @spec start_link(start_opts()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    handle = Keyword.fetch!(opts, :handle)
    owner = Keyword.fetch!(opts, :owner)
    stream_opts = Keyword.get(opts, :opts, [])

    state = %{
      handle: handle,
      owner: owner,
      owner_ref: Process.monitor(owner),
      opts: Keyword.drop(stream_opts, [:worker_daemon_stream_owner]),
      after_event_id: 0,
      poll_interval_ms: positive_integer(stream_opts, :worker_daemon_stream_poll_interval_ms) || @default_poll_interval_ms,
      event_limit: positive_integer(stream_opts, :worker_daemon_stream_event_limit) || @default_event_limit
    }

    {:ok, state, {:continue, :poll}}
  end

  @impl true
  def handle_continue(:poll, state), do: poll(state)

  @impl true
  def handle_info(:poll, state), do: poll(state)

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp poll(%{owner: owner} = state) do
    if Process.alive?(owner) do
      state
      |> poll_session_events()
      |> maybe_poll_session_status()
    else
      {:stop, :normal, state}
    end
  end

  defp poll_session_events(%{handle: %SessionHandle{} = handle, owner: owner, opts: opts, after_event_id: after_event_id, event_limit: event_limit} = state) do
    stream_opts = Keyword.merge(opts, after_event_id: after_event_id, limit: event_limit)

    case handle.client.session_events(handle, stream_opts) do
      {:ok, events} ->
        Enum.each(events, &forward_session_event(handle, owner, &1))
        %{state | after_event_id: max_event_id(events, after_event_id)}

      {:error, _reason} ->
        state
    end
  end

  defp maybe_poll_session_status(%{handle: %SessionHandle{} = handle, opts: opts, owner: owner} = state) do
    case handle.client.session_status(handle, opts) do
      {:ok, status} when is_binary(status) ->
        if Protocol.terminal_status?(status) do
          send_terminal_status(handle, owner, status)
          {:stop, :normal, state}
        else
          Process.send_after(self(), :poll, state.poll_interval_ms)
          {:noreply, state}
        end

      {:error, _reason} ->
        send_terminal_failure(handle, owner)
        {:stop, :normal, state}
    end
  end

  defp forward_session_event(%SessionHandle{} = handle, owner, %{type: "output", data: data}) when is_binary(data) do
    forward_output_data(handle, owner, data)
  end

  defp forward_session_event(_handle, _owner, _event), do: :ok

  defp forward_output_data(_handle, _owner, ""), do: :ok

  defp forward_output_data(%SessionHandle{} = handle, owner, data) when is_binary(data) do
    parts = String.split(data, "\n", trim: false)

    parts
    |> Enum.take(length(parts) - 1)
    |> Enum.each(&send(owner, {handle, {:data, {:eol, &1}}}))

    if not String.ends_with?(data, "\n") do
      case List.last(parts) do
        "" -> :ok
        final_part -> send(owner, {handle, {:data, {:noeol, final_part}}})
      end
    end
  end

  defp send_terminal_status(%SessionHandle{} = handle, owner, status) do
    exit_status = if Status.successful_terminal?(status), do: 0, else: 1
    send(owner, {handle, {:exit_status, exit_status}})
  end

  defp send_terminal_failure(%SessionHandle{} = handle, owner), do: send(owner, {handle, {:exit_status, 1}})

  defp max_event_id(events, default) when is_list(events) do
    events
    |> Enum.map(&Map.get(&1, :event_id))
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> default end)
  end

  defp positive_integer(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value > 0 -> value
      _value -> nil
    end
  end
end
