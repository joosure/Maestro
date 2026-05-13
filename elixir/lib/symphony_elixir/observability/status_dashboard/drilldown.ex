defmodule SymphonyElixir.Observability.StatusDashboard.Drilldown do
  @moduledoc false

  alias SymphonyElixir.Observability.EventStore

  @terminal_drilldown_issue_limit 3
  @terminal_drilldown_recent_event_limit 3
  @terminal_drilldown_session_log_limit 3

  @type format_opts :: %{
          colorize: (String.t(), String.t() -> String.t()),
          truncate_plain: (String.t(), pos_integer() -> String.t()),
          terminal_columns: (-> pos_integer()),
          compact_session_id: (term() -> String.t()),
          ansi_bold: String.t(),
          ansi_cyan: String.t(),
          ansi_gray: String.t()
        }

  @spec payload([map()], [map()]) :: [map()]
  def payload(running, retrying) when is_list(running) and is_list(retrying) do
    running
    |> drilldown_contexts(retrying)
    |> Enum.map(&load_entry/1)
    |> Enum.reject(&(Enum.empty?(&1.recent_events) and Enum.empty?(&1.agent_session_logs)))
  end

  @spec format_section([map()], integer() | nil, format_opts()) :: [String.t()]
  def format_section([], _terminal_columns_override, _opts), do: []

  def format_section(drilldown, terminal_columns_override, opts) when is_list(drilldown) do
    ["│", colorize("├─ Issue drill-down", opts.ansi_bold, opts), "│"] ++
      format_rows(drilldown, terminal_columns_override, opts)
  end

  defp format_rows(drilldown, terminal_columns_override, opts) when is_list(drilldown) do
    terminal_columns = terminal_columns_override || opts.terminal_columns.()
    max_width = max(40, terminal_columns - 5)
    last_index = max(length(drilldown) - 1, 0)

    drilldown
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      lines =
        [
          "│  " <>
            colorize(
              truncate_plain(header(entry, opts), max_width, opts),
              opts.ansi_cyan,
              opts
            )
        ] ++
          maybe_summary_line("recent", entry.recent_events, max_width, opts) ++
          maybe_summary_line("agent ", entry.agent_session_logs, max_width, opts)

      if index < last_index, do: lines ++ ["│"], else: lines
    end)
  end

  defp maybe_summary_line(_label, [], _max_width, _opts), do: []

  defp maybe_summary_line(label, events, max_width, opts) when is_list(events) do
    summary = Enum.map_join(events, " -> ", &(Map.get(&1, "event") || "unknown"))

    ["│    " <> colorize(truncate_plain("#{label}: #{summary}", max_width, opts), opts.ansi_gray, opts)]
  end

  defp header(entry, opts) when is_map(entry) do
    [
      Map.get(entry, :issue_identifier) || "unknown",
      "[#{Map.get(entry, :state) || "unknown"}]",
      context_suffix(entry, opts)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> String.trim()
  end

  defp context_suffix(entry, %{compact_session_id: compact_session_id}) when is_map(entry) do
    [
      Map.get(entry, :run_id) && "run=#{Map.get(entry, :run_id)}",
      Map.get(entry, :session_id) && "session=#{compact_session_id.(Map.get(entry, :session_id))}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp drilldown_contexts(running, retrying) do
    (Enum.map(running, &running_context/1) ++ Enum.map(retrying, &retry_context/1))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce({MapSet.new(), []}, fn context, {seen, acc} ->
      key = {context.issue_id, context.issue_identifier}

      if MapSet.member?(seen, key) do
        {seen, acc}
      else
        {MapSet.put(seen, key), acc ++ [context]}
      end
    end)
    |> elem(1)
    |> Enum.take(@terminal_drilldown_issue_limit)
  end

  defp running_context(entry) when is_map(entry) do
    issue_identifier = Map.get(entry, :identifier) || Map.get(entry, :issue_identifier)

    %{
      issue_id: Map.get(entry, :issue_id),
      issue_identifier: issue_identifier,
      run_id: Map.get(entry, :run_id),
      session_id: Map.get(entry, :session_id),
      state: Map.get(entry, :state)
    }
  end

  defp retry_context(entry) when is_map(entry) do
    issue_identifier = Map.get(entry, :identifier) || Map.get(entry, :issue_identifier)

    %{
      issue_id: Map.get(entry, :issue_id),
      issue_identifier: issue_identifier,
      run_id: Map.get(entry, :run_id),
      session_id: Map.get(entry, :session_id),
      state: "retrying"
    }
  end

  defp load_entry(context) when is_map(context) do
    lookup_context =
      context
      |> Map.take([:issue_id, :issue_identifier, :run_id, :session_id])
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    %{
      issue_identifier: Map.get(context, :issue_identifier) || "unknown",
      state: Map.get(context, :state),
      run_id: Map.get(context, :run_id),
      session_id: Map.get(context, :session_id),
      recent_events:
        EventStore.recent_issue_events(
          lookup_context,
          limit: @terminal_drilldown_recent_event_limit
        ),
      agent_session_logs:
        EventStore.agent_session_logs(
          lookup_context,
          limit: @terminal_drilldown_session_log_limit
        )
    }
  end

  defp truncate_plain(value, width, %{truncate_plain: truncate_plain})
       when is_function(truncate_plain, 2),
       do: truncate_plain.(value, width)

  defp colorize(value, code, %{colorize: colorize}) when is_function(colorize, 2),
    do: colorize.(value, code)
end
