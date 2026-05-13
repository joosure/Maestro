defmodule SymphonyElixir.Observability.StatusDashboard.PresenterOptions do
  @moduledoc false

  alias SymphonyElixir.{Config, HttpServer, Tracker}
  alias SymphonyElixir.Observability.StatusDashboard.Snapshot

  @ansi_reset IO.ANSI.reset()
  @ansi_bold IO.ANSI.bright()
  @ansi_cyan IO.ANSI.cyan()
  @ansi_gray IO.ANSI.light_black()

  @spec format(term()) :: map()
  def format(snapshot_data) do
    %{
      max_agents: Config.settings!().agent.execution.max_concurrent_agents,
      project_link_lines: format_project_link_lines(),
      project_refresh_line: format_project_refresh_line(Snapshot.polling(snapshot_data))
    }
  end

  @spec dashboard_url(String.t(), non_neg_integer() | nil, non_neg_integer() | nil) :: String.t() | nil
  def dashboard_url(_host, nil, _bound_port), do: nil

  def dashboard_url(host, configured_port, bound_port) do
    port = bound_port || configured_port

    if is_integer(port) and port > 0 do
      "http://#{dashboard_url_host(host)}:#{port}/"
    else
      nil
    end
  end

  defp format_project_link_lines do
    project_part =
      case Tracker.project_url() do
        project_url when is_binary(project_url) and project_url != "" ->
          colorize(project_url, @ansi_cyan)

        _ ->
          colorize("n/a", @ansi_gray)
      end

    project_line = colorize("│ Project: ", @ansi_bold) <> project_part

    case dashboard_url() do
      url when is_binary(url) ->
        [project_line, colorize("│ Dashboard: ", @ansi_bold) <> colorize(url, @ansi_cyan)]

      _ ->
        [project_line]
    end
  end

  defp format_project_refresh_line(%{checking?: true}) do
    colorize("│ Next refresh: ", @ansi_bold) <> colorize("checking now…", @ansi_cyan)
  end

  defp format_project_refresh_line(%{next_poll_in_ms: due_in_ms}) when is_integer(due_in_ms) do
    due_in_ms = max(due_in_ms, 0)
    seconds = div(due_in_ms + 999, 1000)
    colorize("│ Next refresh: ", @ansi_bold) <> colorize("#{seconds}s", @ansi_cyan)
  end

  defp format_project_refresh_line(_) do
    colorize("│ Next refresh: ", @ansi_bold) <> colorize("n/a", @ansi_gray)
  end

  defp dashboard_url do
    dashboard_url(Config.settings!().server.host, Config.server_port(), HttpServer.bound_port())
  end

  defp dashboard_url_host(host) when host in ["0.0.0.0", "::", "[::]", ""], do: "127.0.0.1"

  defp dashboard_url_host(host) when is_binary(host) do
    trimmed_host = String.trim(host)

    cond do
      trimmed_host in ["0.0.0.0", "::", "[::]", ""] ->
        "127.0.0.1"

      String.starts_with?(trimmed_host, "[") and String.ends_with?(trimmed_host, "]") ->
        trimmed_host

      String.contains?(trimmed_host, ":") ->
        "[#{trimmed_host}]"

      true ->
        trimmed_host
    end
  end

  defp colorize(value, code) do
    "#{code}#{value}#{@ansi_reset}"
  end
end
