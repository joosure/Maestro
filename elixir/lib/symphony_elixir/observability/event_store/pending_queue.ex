defmodule SymphonyElixir.Observability.EventStore.PendingQueue do
  @moduledoc false

  alias SymphonyElixir.Observability.EventStore.Config

  @counter_key {SymphonyElixir.Observability.EventStore, :pending_event_queue_counter}
  @limit_key {SymphonyElixir.Observability.EventStore, :pending_event_queue_limit}

  @type counter :: :atomics.atomics_ref()

  @spec initialize(pos_integer()) :: :ok
  def initialize(limit) when is_integer(limit) and limit > 0 do
    set_counter(:atomics.new(1, signed: false))
    set_limit(limit)
  end

  @spec set_limit(pos_integer()) :: :ok
  def set_limit(limit) when is_integer(limit) and limit > 0 do
    :persistent_term.put(@limit_key, limit)
  end

  @spec reserve_slot() :: boolean()
  def reserve_slot do
    reserve_slot(counter(), limit())
  end

  @spec release_slot() :: :ok
  def release_slot do
    release_slot(counter())
  end

  @spec limit() :: pos_integer()
  def limit do
    :persistent_term.get(@limit_key, Config.default().pending_event_queue_limit)
  end

  @spec counter() :: counter() | nil
  def counter do
    :persistent_term.get(@counter_key, nil)
  end

  defp reserve_slot(nil, _limit), do: true

  defp reserve_slot(counter, limit) do
    current = :atomics.get(counter, 1)

    cond do
      current >= limit ->
        false

      :atomics.compare_exchange(counter, 1, current, current + 1) == :ok ->
        true

      true ->
        reserve_slot(counter, limit)
    end
  end

  defp release_slot(nil), do: :ok

  defp release_slot(counter) do
    current = :atomics.get(counter, 1)

    cond do
      current <= 0 ->
        :ok

      :atomics.compare_exchange(counter, 1, current, current - 1) == :ok ->
        :ok

      true ->
        release_slot(counter)
    end
  end

  defp set_counter(counter) do
    :persistent_term.put(@counter_key, counter)
  end
end
