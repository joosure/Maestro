defmodule SymphonyWorkerDaemon.Session.Server.Events do
  @moduledoc false

  alias SymphonyElixir.Observability.Redaction

  @default_event_limit 100
  @max_event_limit 500

  @spec append_output(map(), String.t(), binary()) :: map()
  def append_output(state, stream, chunk) when is_binary(chunk) do
    byte_count = byte_size(chunk)

    if state.output_bytes + byte_count > state.output_buffer_limit do
      state = %{state | output_bytes: state.output_bytes + byte_count}

      if state.output_truncated? do
        state
      else
        state
        |> Map.put(:output_truncated?, true)
        |> append_event(%{
          "type" => "output_truncated",
          "stream" => stream
        })
      end
    else
      state
      |> Map.update!(:output_bytes, &(&1 + byte_count))
      |> append_event(%{"type" => "output", "stream" => stream, "data" => Redaction.redact_string(chunk)})
    end
  end

  defp append_event(state, event) when is_map(event) do
    event =
      event
      |> Map.put("event_id", state.next_event_id)
      |> Map.put("timestamp_ms", System.system_time(:millisecond))

    %{state | events: [event | state.events], next_event_id: state.next_event_id + 1, updated_at_ms: event["timestamp_ms"]}
  end

  @spec event_window(map(), keyword()) :: [map()]
  def event_window(state, opts) when is_list(opts) do
    after_event_id = Keyword.get(opts, :after_event_id) |> normalize_non_negative_integer()
    limit = opts |> Keyword.get(:limit, @default_event_limit) |> normalize_limit()

    state.events
    |> Enum.reverse()
    |> Enum.filter(fn event -> Map.get(event, "event_id", 0) > after_event_id end)
    |> Enum.take(limit)
  end

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> 0
    end
  end

  defp normalize_non_negative_integer(_value), do: 0

  defp normalize_limit(value) when is_integer(value), do: value |> max(1) |> min(@max_event_limit)

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize_limit(integer)
      _invalid -> @default_event_limit
    end
  end

  defp normalize_limit(_value), do: @default_event_limit
end
