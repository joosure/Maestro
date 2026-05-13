defmodule SymphonyElixir.Observability.StatusDashboard.Presenter do
  @moduledoc false

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Observability.StatusDashboard.{Drilldown, RateLimits}

  @running_id_width 8
  @running_stage_width 14
  @running_pid_width 8
  @running_age_width 12
  @running_tokens_width 10
  @running_session_width 14
  @running_event_default_width 44
  @running_event_min_width 12
  @running_row_chrome_width 10
  @default_terminal_columns 115

  @ansi_reset IO.ANSI.reset()
  @ansi_bold IO.ANSI.bright()
  @ansi_blue IO.ANSI.blue()
  @ansi_cyan IO.ANSI.cyan()
  @ansi_dim IO.ANSI.faint()
  @ansi_green IO.ANSI.green()
  @ansi_red IO.ANSI.red()
  @ansi_orange IO.ANSI.yellow()
  @ansi_yellow IO.ANSI.yellow()
  @ansi_magenta IO.ANSI.magenta()
  @ansi_gray IO.ANSI.light_black()

  @spec format_snapshot_content(term(), number(), integer() | nil, map()) :: String.t()
  def format_snapshot_content(snapshot_data, tps, terminal_columns_override \\ nil, opts) do
    project_link_lines = Map.fetch!(opts, :project_link_lines)
    project_refresh_line = Map.fetch!(opts, :project_refresh_line)

    case snapshot_data do
      {:ok, %{running: running, retrying: retrying} = snapshot} ->
        agent_totals = Map.get(snapshot, :agent_totals) || %{}
        rate_limits = Map.get(snapshot, :agent_rate_limits)
        drilldown = Map.get(snapshot, :drilldown, [])
        agent_input_tokens = Map.get(agent_totals, :input_tokens, 0)
        agent_output_tokens = Map.get(agent_totals, :output_tokens, 0)
        agent_total_tokens = Map.get(agent_totals, :total_tokens, 0)
        agent_seconds_running = Map.get(agent_totals, :seconds_running, 0)
        agent_count = length(running)
        max_agents = Map.fetch!(opts, :max_agents)
        running_event_width = running_event_width(terminal_columns_override)
        running_rows = format_running_rows(running, running_event_width)
        running_to_backoff_spacer = if(running == [], do: [], else: ["│"])
        backoff_rows = format_retry_rows(retrying)

        ([
           colorize("╭─ SYMPHONY STATUS", @ansi_bold),
           colorize("│ Agents: ", @ansi_bold) <>
             colorize("#{agent_count}", @ansi_green) <>
             colorize("/", @ansi_gray) <>
             colorize("#{max_agents}", @ansi_gray),
           colorize("│ Throughput: ", @ansi_bold) <> colorize("#{format_tps(tps)} tps", @ansi_cyan),
           colorize("│ Runtime: ", @ansi_bold) <>
             colorize(format_runtime_seconds(agent_seconds_running), @ansi_magenta),
           colorize("│ Tokens: ", @ansi_bold) <>
             colorize("in #{format_count(agent_input_tokens)}", @ansi_yellow) <>
             colorize(" | ", @ansi_gray) <>
             colorize("out #{format_count(agent_output_tokens)}", @ansi_yellow) <>
             colorize(" | ", @ansi_gray) <>
             colorize("total #{format_count(agent_total_tokens)}", @ansi_yellow),
           colorize("│ Rate Limits: ", @ansi_bold) <>
             RateLimits.format(rate_limits, rate_limit_format_opts()),
           project_link_lines,
           project_refresh_line,
           colorize("├─ Running", @ansi_bold),
           "│",
           running_table_header_row(running_event_width),
           running_table_separator_row(running_event_width)
         ] ++
           running_rows ++
           running_to_backoff_spacer ++
           [colorize("├─ Backoff queue", @ansi_bold), "│"] ++
           backoff_rows ++
           Drilldown.format_section(
             drilldown,
             terminal_columns_override,
             drilldown_format_opts()
           ) ++
           [closing_border()])
        |> List.flatten()
        |> Enum.join("\n")

      :error ->
        [
          colorize("╭─ SYMPHONY STATUS", @ansi_bold),
          colorize("│ Orchestrator snapshot unavailable", @ansi_red),
          colorize("│ Throughput: ", @ansi_bold) <> colorize("#{format_tps(tps)} tps", @ansi_cyan),
          project_link_lines,
          project_refresh_line,
          closing_border()
        ]
        |> List.flatten()
        |> Enum.join("\n")
    end
  end

  @spec format_running_summary(map(), integer() | nil) :: String.t()
  def format_running_summary(running_entry, terminal_columns_override \\ nil) do
    do_format_running_summary(running_entry, running_event_width(terminal_columns_override))
  end

  @spec format_tps(number()) :: String.t()
  def format_tps(value) when is_number(value) do
    value
    |> trunc()
    |> Integer.to_string()
    |> group_thousands()
  end

  defp format_running_rows(running, running_event_width) do
    if running == [] do
      [
        "│  " <> colorize("No active agents", @ansi_gray),
        "│"
      ]
    else
      running
      |> Enum.sort_by(& &1.identifier)
      |> Enum.map(&do_format_running_summary(&1, running_event_width))
    end
  end

  # credo:disable-for-next-line
  defp do_format_running_summary(running_entry, running_event_width) do
    issue = format_cell(running_entry.identifier || "unknown", @running_id_width)
    state = running_entry.state || "unknown"
    state_display = format_cell(to_string(state), @running_stage_width)
    session = running_entry.session_id |> compact_session_id() |> format_cell(@running_session_width)
    pid = format_cell(running_process_pid(running_entry), @running_pid_width)
    total_tokens = running_total_tokens(running_entry)
    runtime_seconds = running_entry.runtime_seconds || 0
    turn_count = Map.get(running_entry, :turn_count, 0)
    age = format_cell(format_runtime_and_turns(runtime_seconds, turn_count), @running_age_width)
    event = running_last_event(running_entry)
    event_label = format_cell(summarize_message(running_last_message(running_entry)), running_event_width)

    tokens = format_count(total_tokens) |> format_cell(@running_tokens_width, :right)

    status_color =
      cond do
        event in [:none, "none"] -> @ansi_red
        agent_event?(event, "/token_count") -> @ansi_yellow
        agent_event?(event, "/task_started") -> @ansi_green
        event == "turn_completed" -> @ansi_magenta
        true -> @ansi_blue
      end

    [
      "│ ",
      status_dot(status_color),
      " ",
      colorize(issue, @ansi_cyan),
      " ",
      colorize(state_display, status_color),
      " ",
      colorize(pid, @ansi_yellow),
      " ",
      colorize(age, @ansi_magenta),
      " ",
      colorize(tokens, @ansi_yellow),
      " ",
      colorize(session, @ansi_cyan),
      " ",
      colorize(event_label, status_color)
    ]
    |> Enum.join("")
  end

  defp agent_event?(event, suffix) when is_binary(event) and is_binary(suffix) do
    String.ends_with?(event, suffix)
  end

  defp agent_event?(_event, _suffix), do: false

  defp format_retry_rows(retrying) do
    if retrying == [] do
      ["│  " <> colorize("No queued retries", @ansi_gray)]
    else
      retrying
      |> Enum.sort_by(& &1.due_in_ms)
      |> Enum.map_join(", ", &format_retry_summary/1)
      |> String.split(", ")
    end
  end

  defp running_process_pid(running_entry) do
    Map.get(running_entry, :agent_process_pid) || "n/a"
  end

  defp running_total_tokens(running_entry) do
    Map.get(running_entry, :agent_total_tokens) || 0
  end

  defp running_last_event(running_entry) do
    Map.get(running_entry, :last_agent_event) || "none"
  end

  defp running_last_message(running_entry) do
    Map.get(running_entry, :last_agent_message)
  end

  defp format_retry_summary(retry_entry) do
    issue_id = retry_entry.issue_id || "unknown"
    identifier = retry_entry.identifier || issue_id
    attempt = retry_entry.attempt || 0
    due_in_ms = retry_entry.due_in_ms || 0
    error = format_retry_error(retry_entry.error)

    "│  #{colorize("↻", @ansi_orange)} " <>
      colorize("#{identifier}", @ansi_red) <>
      " " <>
      colorize("attempt=#{attempt}", @ansi_yellow) <>
      colorize(" in ", @ansi_dim) <>
      colorize(next_in_words(due_in_ms), @ansi_cyan) <>
      error
  end

  defp next_in_words(due_in_ms) when is_integer(due_in_ms) do
    secs = div(due_in_ms, 1000)
    millis = rem(due_in_ms, 1000)
    "#{secs}.#{String.pad_leading(to_string(millis), 3, "0")}s"
  end

  defp next_in_words(_), do: "n/a"

  defp format_retry_error(error) when is_binary(error) do
    sanitized =
      error
      |> String.replace("\\r\\n", " ")
      |> String.replace("\\r", " ")
      |> String.replace("\\n", " ")
      |> String.replace("\r\n", " ")
      |> String.replace("\r", " ")
      |> String.replace("\n", " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if sanitized == "" do
      ""
    else
      " " <> colorize("error=#{truncate(sanitized, 96)}", @ansi_dim)
    end
  end

  defp format_retry_error(_), do: ""

  defp format_runtime_seconds(seconds) when is_integer(seconds) do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{mins}m #{secs}s"
  end

  defp format_runtime_seconds(seconds) when is_binary(seconds), do: seconds
  defp format_runtime_seconds(_), do: "0m 0s"

  defp format_runtime_and_turns(seconds, turn_count) when is_integer(turn_count) and turn_count > 0 do
    "#{format_runtime_seconds(seconds)} / #{turn_count}"
  end

  defp format_runtime_and_turns(seconds, _turn_count), do: format_runtime_seconds(seconds)

  defp format_count(nil), do: "0"

  defp format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> group_thousands()
  end

  defp format_count(value) when is_binary(value) do
    value
    |> String.trim()
    |> Integer.parse()
    |> case do
      {number, ""} -> group_thousands(Integer.to_string(number))
      _ -> value
    end
  end

  defp format_count(value), do: to_string(value)

  defp running_table_header_row(running_event_width) do
    header =
      [
        format_cell("ID", @running_id_width),
        format_cell("STAGE", @running_stage_width),
        format_cell("PID", @running_pid_width),
        format_cell("AGE / TURN", @running_age_width),
        format_cell("TOKENS", @running_tokens_width),
        format_cell("SESSION", @running_session_width),
        format_cell("EVENT", running_event_width)
      ]
      |> Enum.join(" ")

    "│   " <> colorize(header, @ansi_gray)
  end

  defp running_table_separator_row(running_event_width) do
    separator_width =
      @running_id_width +
        @running_stage_width +
        @running_pid_width +
        @running_age_width +
        @running_tokens_width +
        @running_session_width +
        running_event_width + 6

    "│   " <> colorize(String.duplicate("─", separator_width), @ansi_gray)
  end

  defp running_event_width(terminal_columns) do
    terminal_columns = terminal_columns || terminal_columns()

    max(
      @running_event_min_width,
      terminal_columns - fixed_running_width() - @running_row_chrome_width
    )
  end

  defp fixed_running_width do
    @running_id_width +
      @running_stage_width +
      @running_pid_width +
      @running_age_width +
      @running_tokens_width +
      @running_session_width
  end

  defp terminal_columns do
    case :io.columns() do
      {:ok, columns} when is_integer(columns) and columns > 0 ->
        columns

      _ ->
        terminal_columns_from_env()
    end
  end

  defp terminal_columns_from_env do
    case System.get_env("COLUMNS") do
      nil ->
        fixed_running_width() + @running_row_chrome_width + @running_event_default_width

      value ->
        case Integer.parse(String.trim(value)) do
          {columns, ""} when columns > 0 -> columns
          _ -> @default_terminal_columns
        end
    end
  end

  defp format_cell(value, width, align \\ :left) do
    value =
      value
      |> to_string()
      |> String.replace("\n", " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> truncate_plain(width)

    case align do
      :right -> String.pad_leading(value, width)
      _ -> String.pad_trailing(value, width)
    end
  end

  defp truncate_plain(value, width) do
    if byte_size(value) <= width do
      value
    else
      String.slice(value, 0, width - 3) <> "..."
    end
  end

  defp compact_session_id(nil), do: "n/a"
  defp compact_session_id(session_id) when not is_binary(session_id), do: "n/a"

  defp compact_session_id(session_id) do
    if String.length(session_id) > 10 do
      String.slice(session_id, 0, 4) <> "..." <> String.slice(session_id, -6, 6)
    else
      session_id
    end
  end

  defp group_thousands(value) when is_binary(value) do
    sign = if String.starts_with?(value, "-"), do: "-", else: ""
    unsigned = if sign == "", do: value, else: String.slice(value, 1, String.length(value) - 1)

    unsigned
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
    |> prepend(sign)
  end

  defp prepend("", value), do: value
  defp prepend(prefix, value), do: prefix <> value

  defp status_dot(color_code) do
    colorize("●", color_code)
  end

  defp closing_border, do: "╰─"

  defp colorize(value, code) do
    "#{code}#{value}#{@ansi_reset}"
  end

  defp rate_limit_format_opts do
    %{
      colorize: &colorize/2,
      truncate: &truncate/2,
      format_count: &format_count/1,
      ansi_gray: @ansi_gray,
      ansi_yellow: @ansi_yellow,
      ansi_cyan: @ansi_cyan,
      ansi_green: @ansi_green
    }
  end

  defp drilldown_format_opts do
    %{
      colorize: &colorize/2,
      truncate_plain: &truncate_plain/2,
      terminal_columns: &terminal_columns/0,
      compact_session_id: &compact_session_id/1,
      ansi_bold: @ansi_bold,
      ansi_cyan: @ansi_cyan,
      ansi_gray: @ansi_gray
    }
  end

  defp summarize_message(message), do: AgentProvider.present_message(message)

  defp truncate(value, max) when byte_size(value) > max do
    value |> String.slice(0, max) |> Kernel.<>("...")
  end

  defp truncate(value, _max), do: value
end
