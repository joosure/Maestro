defmodule SymphonyElixir.Observability.StatusDashboard.Terminal do
  @moduledoc false

  alias SymphonyElixir.Observability.StatusDashboard.RenderFailure

  @ansi_reset IO.ANSI.reset()
  @ansi_bold IO.ANSI.bright()
  @ansi_red IO.ANSI.red()

  @spec render_offline_status() :: :ok
  def render_offline_status do
    render_offline_status(&render_to_terminal/1)
  end

  @spec render_offline_status((String.t() -> term())) :: :ok
  def render_offline_status(render_fun) when is_function(render_fun, 1) do
    content =
      [
        colorize("╭─ SYMPHONY STATUS", @ansi_bold),
        colorize("│ app_status=offline", @ansi_red),
        closing_border()
      ]
      |> Enum.join("\n")

    render_fun.(content)
    :ok
  rescue
    error ->
      RenderFailure.emit(
        :dashboard_offline_render_failed,
        "offline_status",
        error
      )

      :ok
  catch
    kind, reason ->
      RenderFailure.emit(
        :dashboard_offline_render_failed,
        "offline_status",
        {kind, reason}
      )

      :ok
  end

  @spec render_to_terminal(String.t()) :: :ok
  def render_to_terminal(content) do
    IO.write([
      IO.ANSI.home(),
      IO.ANSI.clear(),
      normalize_status_lines(content),
      "\n"
    ])
  end

  @spec render_content(map(), String.t(), integer()) :: map()
  def render_content(state, content, now_ms) do
    state.render_fun.(content)

    %{
      state
      | last_rendered_content: content,
        last_rendered_at_ms: now_ms,
        pending_content: nil,
        flush_timer_ref: nil
    }
  rescue
    error ->
      RenderFailure.emit(
        :dashboard_terminal_frame_render_failed,
        "terminal_frame",
        error
      )

      %{state | pending_content: nil, flush_timer_ref: nil}
  catch
    kind, reason ->
      RenderFailure.emit(
        :dashboard_terminal_frame_render_failed,
        "terminal_frame",
        {kind, reason}
      )

      %{state | pending_content: nil, flush_timer_ref: nil}
  end

  defp normalize_status_lines(content), do: content

  defp closing_border, do: "╰─"

  defp colorize(value, code) do
    "#{code}#{value}#{@ansi_reset}"
  end
end
