defmodule SymphonyElixir.Observability.EventBuffer do
  @moduledoc """
  Small bounded FIFO buffer used by in-memory observability projections.
  """

  defstruct limit: 0, entries: :queue.new()

  @opaque t :: %__MODULE__{
            limit: pos_integer(),
            entries: term()
          }

  @spec new(pos_integer()) :: t()
  def new(limit) when is_integer(limit) and limit > 0 do
    %__MODULE__{limit: limit}
  end

  @spec append(t(), term()) :: t()
  def append(%__MODULE__{limit: limit, entries: entries} = buffer, entry)
      when is_integer(limit) and limit > 0 do
    entries = :queue.in(entry, entries)
    entries = trim(entries, limit)
    %{buffer | entries: entries}
  end

  @spec to_list(t()) :: [term()]
  def to_list(%__MODULE__{entries: entries}) do
    :queue.to_list(entries)
  end

  @spec resize(t(), pos_integer()) :: t()
  def resize(%__MODULE__{} = buffer, limit) when is_integer(limit) and limit > 0 do
    buffer
    |> to_list()
    |> Enum.take(-limit)
    |> Enum.reduce(new(limit), fn entry, acc -> append(acc, entry) end)
  end

  defp trim(entries, limit) do
    if :queue.len(entries) > limit do
      {{:value, _discarded}, remaining} = :queue.out(entries)
      trim(remaining, limit)
    else
      entries
    end
  end
end
