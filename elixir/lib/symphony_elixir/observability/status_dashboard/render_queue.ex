defmodule SymphonyElixir.Observability.StatusDashboard.RenderQueue do
  @moduledoc false

  @minimum_idle_rerender_ms 1_000

  @type renderer :: (map(), String.t(), integer() -> map())

  @spec render_due?(map(), term(), integer()) :: boolean()
  def render_due?(state, snapshot_data, now_ms) do
    snapshot_data != state.last_snapshot_fingerprint or periodic_rerender_due?(state, now_ms)
  end

  @spec put_snapshot_fingerprint(map(), term()) :: map()
  def put_snapshot_fingerprint(state, snapshot_data) do
    if snapshot_data == state.last_snapshot_fingerprint do
      state
    else
      Map.put(state, :last_snapshot_fingerprint, snapshot_data)
    end
  end

  @spec enqueue(map(), String.t(), integer(), renderer()) :: map()
  def enqueue(state, content, now_ms, render_content_fun) do
    cond do
      content == state.last_rendered_content ->
        state

      render_now?(state, now_ms) ->
        render_content_fun.(state, content, now_ms)

      true ->
        schedule_flush_render(%{state | pending_content: content}, now_ms)
    end
  end

  @spec flush_pending(map(), integer(), renderer()) :: map()
  def flush_pending(state, now_ms, render_content_fun) do
    case state.pending_content do
      nil ->
        %{state | flush_timer_ref: nil}

      content ->
        next_state =
          state
          |> Map.put(:flush_timer_ref, nil)
          |> Map.put(:pending_content, nil)

        render_content_fun.(next_state, content, now_ms)
    end
  end

  defp periodic_rerender_due?(%{last_rendered_at_ms: nil}, _now_ms), do: true

  defp periodic_rerender_due?(%{last_rendered_at_ms: last_rendered_at_ms}, now_ms)
       when is_integer(last_rendered_at_ms) do
    now_ms - last_rendered_at_ms >= @minimum_idle_rerender_ms
  end

  defp periodic_rerender_due?(_state, _now_ms), do: false

  defp render_now?(%{last_rendered_at_ms: nil, flush_timer_ref: nil}, _now_ms), do: true

  defp render_now?(%{last_rendered_at_ms: last_rendered_at_ms, render_interval_ms: render_interval_ms}, now_ms)
       when is_integer(last_rendered_at_ms) and is_integer(render_interval_ms) do
    now_ms - last_rendered_at_ms >= render_interval_ms
  end

  defp render_now?(_state, _now_ms), do: false

  defp schedule_flush_render(%{flush_timer_ref: timer_ref} = state, _now_ms) when is_reference(timer_ref),
    do: state

  defp schedule_flush_render(state, now_ms) do
    delay_ms = flush_delay_ms(state, now_ms)
    timer_ref = make_ref()
    Process.send_after(self(), {:flush_render, timer_ref}, delay_ms)
    %{state | flush_timer_ref: timer_ref}
  end

  defp flush_delay_ms(%{last_rendered_at_ms: nil}, _now_ms), do: 1

  defp flush_delay_ms(
         %{last_rendered_at_ms: last_rendered_at_ms, render_interval_ms: render_interval_ms},
         now_ms
       ) do
    remaining = render_interval_ms - (now_ms - last_rendered_at_ms)
    max(1, remaining)
  end
end
