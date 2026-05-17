defmodule SymphonyElixir.Observability.EventStore.Index do
  @moduledoc false

  alias SymphonyElixir.Observability.EventStore.Buffer

  @type entry :: %{
          required(:buffer) => Buffer.t(),
          required(:last_seen_at) => integer()
        }

  @type t :: %{optional(String.t()) => entry()}

  @spec append(t(), String.t() | nil, map(), pos_integer(), pos_integer()) :: t()
  def append(index, nil, _record, _limit, _index_key_limit), do: index
  def append(index, "", _record, _limit, _index_key_limit), do: index

  def append(index, value, record, limit, index_key_limit)
      when is_map(index) and is_binary(value) and is_integer(limit) and limit > 0 do
    now_ms = System.monotonic_time(:millisecond)
    entry = Map.get(index, value, %{buffer: Buffer.new(limit), last_seen_at: now_ms})

    updated_entry = %{
      buffer: Buffer.append(entry.buffer, record),
      last_seen_at: now_ms
    }

    index
    |> Map.put(value, updated_entry)
    |> prune(index_key_limit)
  end

  @spec resize(t(), pos_integer(), pos_integer()) :: t()
  def resize(index, limit, index_key_limit)
      when is_map(index) and is_integer(limit) and limit > 0 do
    index
    |> Map.new(fn {key, %{buffer: buffer} = entry} ->
      {key, %{entry | buffer: Buffer.resize(buffer, limit)}}
    end)
    |> prune(index_key_limit)
  end

  @spec records(t(), String.t() | nil) :: [map()]
  def records(index, value) when is_map(index) and is_binary(value) and value != "" do
    case Map.get(index, value) do
      %{buffer: buffer} -> Buffer.to_list(buffer)
      _entry -> []
    end
  end

  def records(_index, _value), do: []

  defp prune(index, index_key_limit)
       when is_map(index) and is_integer(index_key_limit) and map_size(index) > index_key_limit do
    drop_count = map_size(index) - index_key_limit

    keys_to_drop =
      index
      |> Enum.sort_by(fn {_key, entry} -> entry.last_seen_at end)
      |> Enum.take(drop_count)
      |> Enum.map(&elem(&1, 0))

    Map.drop(index, keys_to_drop)
  end

  defp prune(index, _index_key_limit), do: index
end
