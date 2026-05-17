defmodule SymphonyElixirWeb.DashboardLive do
  @moduledoc """
  Live observability dashboard for Symphony.
  """

  use Phoenix.LiveView, layout: {SymphonyElixirWeb.Layouts, :app}

  alias SymphonyElixir.Observability.{AlertContract, DynamicToolMetrics}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixirWeb.Observability.{Paths, PubSub, Status}

  alias SymphonyElixirWeb.{
    BrowserPaths,
    Presenter,
    RuntimeConfig
  }

  @runtime_tick_ms 1_000
  @alert_code_key AlertContract.code_key()
  @alert_category_key AlertContract.category_key()
  @alert_count_key AlertContract.count_key()
  @alert_metric_key AlertContract.metric_key()
  @alert_message_key AlertContract.message_key()
  @alert_critical AlertContract.critical()
  @alert_warning AlertContract.warning()

  @impl true
  def mount(params, _session, socket) do
    connected = connected?(socket)
    live_action = Map.get(socket.assigns, :live_action, :index)
    issue_identifier = Map.get(params, "issue_identifier")

    socket =
      socket
      |> assign(:issue_identifier, issue_identifier)
      |> assign(:payload, load_payload(live_action, issue_identifier, :mount))
      |> assign(:now, DateTime.utc_now())

    subscription_result =
      if connected do
        result =
          case PubSub.subscribe() do
            :ok ->
              :ok

            {:error, reason} = error ->
              emit_dashboard_live_event(
                :warning,
                :dashboard_live_subscription_failed,
                %{
                  error: inspect(reason),
                  result_summary: "connected=true"
                }
              )

              error
          end

        schedule_runtime_tick()
        result
      else
        :skipped
      end

    emit_dashboard_live_event(
      :info,
      :dashboard_live_mounted,
      %{
        issue_identifier: issue_identifier,
        result_summary: "connected=#{connected} subscription=#{subscription_summary(subscription_result)} live_action=#{live_action}",
        message: "dashboard_live_mounted connected=#{connected} subscription=#{subscription_summary(subscription_result)} live_action=#{live_action}#{issue_identifier_suffix(issue_identifier)}"
      }
    )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    issue_identifier = Map.get(params, "issue_identifier")

    {:noreply,
     socket
     |> assign(:issue_identifier, issue_identifier)
     |> assign(:payload, load_payload(socket.assigns.live_action, issue_identifier, :params))}
  end

  @impl true
  def handle_info(:runtime_tick, socket) do
    schedule_runtime_tick()
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  @impl true
  def handle_info(:observability_updated, socket) do
    {:noreply,
     socket
     |> assign(
       :payload,
       load_payload(socket.assigns.live_action, socket.assigns.issue_identifier, :refresh)
     )
     |> assign(:now, DateTime.utc_now())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @live_action == :issue do %>
      <%= issue_page(assigns) %>
    <% else %>
      <%= index_page(assigns) %>
    <% end %>
    """
  end

  defp index_page(assigns) do
    ~H"""
    <section class="dashboard-shell">
      <header class="hero-card">
        <div class="hero-grid">
          <div>
            <p class="eyebrow">
              Symphony Observability
            </p>
            <h1 class="hero-title">
              Operations Dashboard
            </h1>
            <p class="hero-copy">
              Current state, retry pressure, token usage, and orchestration health for the active Symphony runtime.
            </p>
          </div>

          <div class="status-stack">
            <span class="status-badge status-badge-live">
              <span class="status-badge-dot"></span>
              Live
            </span>
            <span class="status-badge status-badge-offline">
              <span class="status-badge-dot"></span>
              Offline
            </span>
          </div>
        </div>
      </header>

      <%= if @payload[:error] do %>
        <section class="error-card">
          <h2 class="error-title">
            Snapshot unavailable
          </h2>
          <p class="error-copy">
            <strong><%= @payload.error.code %>:</strong> <%= @payload.error.message %>
          </p>
        </section>
      <% else %>
        <section class="metric-grid">
          <article class="metric-card">
            <p class="metric-label">Running</p>
            <p class="metric-value numeric"><%= @payload.counts.running %></p>
            <p class="metric-detail">Active issue sessions in the current runtime.</p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Retrying</p>
            <p class="metric-value numeric"><%= @payload.counts.retrying %></p>
            <p class="metric-detail">Issues waiting for the next retry window.</p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Total tokens</p>
            <p class="metric-value numeric"><%= format_int(Map.get(agent_totals(@payload), :total_tokens, 0)) %></p>
            <p class="metric-detail numeric">
              In <%= format_int(Map.get(agent_totals(@payload), :input_tokens, 0)) %> / Out <%= format_int(Map.get(agent_totals(@payload), :output_tokens, 0)) %>
            </p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Runtime</p>
            <p class="metric-value numeric"><%= format_runtime_seconds(total_runtime_seconds(@payload, @now)) %></p>
            <p class="metric-detail">Total agent runtime across completed and active sessions.</p>
          </article>
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Rate limits</h2>
              <p class="section-copy">Latest upstream rate-limit snapshot, when available.</p>
            </div>
          </div>

          <pre class="code-panel"><%= pretty_value(agent_rate_limits(@payload)) %></pre>
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Dynamic tools</h2>
              <p class="section-copy">Workflow tool usage across the active runtime.</p>
            </div>
          </div>

          <div class="metric-grid">
            <article class="metric-card">
              <p class="metric-label">Typed hits</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.typed_tool_hits()) %></p>
              <p class="metric-detail">Successful typed workflow tool executions.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Raw attempts</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.raw_tool_attempts()) %></p>
              <p class="metric-detail">Rejected or failed raw tool attempts.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Fallback</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.fallback_count()) %></p>
              <p class="metric-detail">Operator migration fallback calls.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Unsupported</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.unsupported_tool_count()) %></p>
              <p class="metric-detail">Calls blocked before source execution.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Unavailable</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.provider_capability_unavailable_count()) %></p>
              <p class="metric-detail">Provider capabilities reported as unavailable.</p>
            </article>
          </div>

          <.dynamic_tool_alerts payload={@payload} />
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Recent events</h2>
              <p class="section-copy">Latest structured observability events across the active runtime.</p>
            </div>
          </div>

          <%= if Map.get(@payload, :recent_events, []) == [] do %>
            <p class="empty-state">No structured events captured yet.</p>
          <% else %>
            <div class="table-wrap">
              <table class="data-table" style="min-width: 920px;">
                <thead>
                  <tr>
                    <th>When</th>
                    <th>Issue</th>
                    <th>Event</th>
                    <th>Component</th>
                    <th>Message</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={event <- Map.get(@payload, :recent_events, [])}>
                    <td class="mono"><%= event["timestamp"] || "n/a" %></td>
                    <td>
                      <div class="issue-stack">
                        <%= if event["issue_identifier"] do %>
                          <a class="issue-id" href={issue_live_path(event["issue_identifier"])}>
                            <%= event_issue_label(event) %>
                          </a>
                        <% else %>
                          <span class="issue-id"><%= event_issue_label(event) %></span>
                        <% end %>
                        <span :if={event["run_id"]} class="muted mono">run=<%= event["run_id"] %></span>
                      </div>
                    </td>
                    <td class="mono"><%= event["event"] || "n/a" %></td>
                    <td class="mono"><%= event["component"] || "n/a" %></td>
                    <td>
                      <div class="detail-stack">
                        <span class="event-text" title={event["message"] || "n/a"}>
                          <%= event["message"] || "n/a" %>
                        </span>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Running sessions</h2>
              <p class="section-copy">Active issues, last known agent activity, and token usage.</p>
            </div>
          </div>

          <%= if @payload.running == [] do %>
            <p class="empty-state">No active sessions.</p>
          <% else %>
            <div class="table-wrap">
              <table class="data-table data-table-running">
                <colgroup>
                  <col style="width: 12rem;" />
                  <col style="width: 8rem;" />
                  <col style="width: 7.5rem;" />
                  <col style="width: 8.5rem;" />
                  <col />
                  <col style="width: 10rem;" />
                </colgroup>
                <thead>
                  <tr>
                    <th>Issue</th>
                    <th>State</th>
                    <th>Session</th>
                    <th>Runtime / turns</th>
                    <th>Agent update</th>
                    <th>Tokens</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={entry <- @payload.running}>
                    <td>
                      <div class="issue-stack">
                        <a class="issue-id" href={issue_live_path(entry.issue_identifier)}><%= entry.issue_identifier %></a>
                        <a class="issue-link" href={issue_live_path(entry.issue_identifier)}>Live details</a>
                        <a class="issue-link" href={Paths.issue_path(entry.issue_identifier)}>JSON details</a>
                      </div>
                    </td>
                    <td>
                      <span class={state_badge_class(entry.state)}>
                        <%= entry.state %>
                      </span>
                    </td>
                    <td>
                      <div class="session-stack">
                        <%= if entry.session_id do %>
                          <button
                            type="button"
                            class="subtle-button"
                            data-label="Copy ID"
                            data-copy={entry.session_id}
                            onclick="navigator.clipboard.writeText(this.dataset.copy); this.textContent = 'Copied'; clearTimeout(this._copyTimer); this._copyTimer = setTimeout(() => { this.textContent = this.dataset.label }, 1200);"
                          >
                            Copy ID
                          </button>
                        <% else %>
                          <span class="muted">n/a</span>
                        <% end %>
                      </div>
                    </td>
                    <td class="numeric"><%= format_runtime_and_turns(entry.started_at, entry.turn_count, @now) %></td>
                    <td>
                      <div class="detail-stack">
                        <span
                          class="event-text"
                          title={entry.last_message || to_string(entry.last_event || "n/a")}
                        ><%= entry.last_message || to_string(entry.last_event || "n/a") %></span>
                        <span class="muted event-meta">
                          <%= entry.last_event || "n/a" %>
                          <%= if entry.last_event_at do %>
                            · <span class="mono numeric"><%= entry.last_event_at %></span>
                          <% end %>
                        </span>
                      </div>
                    </td>
                    <td>
                      <div class="token-stack numeric">
                        <span>Total: <%= format_int(entry.tokens.total_tokens) %></span>
                        <span class="muted">In <%= format_int(entry.tokens.input_tokens) %> / Out <%= format_int(entry.tokens.output_tokens) %></span>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Retry queue</h2>
              <p class="section-copy">Issues waiting for the next retry window.</p>
            </div>
          </div>

          <%= if @payload.retrying == [] do %>
            <p class="empty-state">No issues are currently backing off.</p>
          <% else %>
            <div class="table-wrap">
              <table class="data-table" style="min-width: 680px;">
                <thead>
                  <tr>
                    <th>Issue</th>
                    <th>Attempt</th>
                    <th>Due at</th>
                    <th>Error</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={entry <- @payload.retrying}>
                    <td>
                      <div class="issue-stack">
                        <a class="issue-id" href={issue_live_path(entry.issue_identifier)}><%= entry.issue_identifier %></a>
                        <a class="issue-link" href={issue_live_path(entry.issue_identifier)}>Live details</a>
                        <a class="issue-link" href={Paths.issue_path(entry.issue_identifier)}>JSON details</a>
                      </div>
                    </td>
                    <td><%= entry.attempt %></td>
                    <td class="mono"><%= entry.due_at || "n/a" %></td>
                    <td><%= entry.error || "n/a" %></td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>
      <% end %>
    </section>
    """
  end

  defp issue_page(assigns) do
    ~H"""
    <section class="dashboard-shell">
      <header class="hero-card">
        <div class="hero-grid">
          <div>
            <p class="eyebrow">
              Symphony Observability
            </p>
            <h1 class="hero-title">
              Issue <%= @issue_identifier || "Unknown" %>
            </h1>
            <p class="hero-copy">
              Structured runtime history, recent events, and agent session logs for this issue.
            </p>
            <p class="metric-detail">
              <a class="issue-link" href="/">Back to dashboard</a>
              <%= if @issue_identifier do %>
                · <a class="issue-link" href={Paths.issue_path(@issue_identifier)}>JSON details</a>
              <% end %>
            </p>
          </div>

          <div class="status-stack">
            <span :if={!@payload[:error]} class={state_badge_class(Map.get(@payload, :status, Status.unknown()))}>
              <%= Map.get(@payload, :status, Status.unknown()) %>
            </span>
            <span class="status-badge status-badge-live">
              <span class="status-badge-dot"></span>
              Live
            </span>
            <span class="status-badge status-badge-offline">
              <span class="status-badge-dot"></span>
              Offline
            </span>
          </div>
        </div>
      </header>

      <%= if @payload[:error] do %>
        <section class="error-card">
          <h2 class="error-title">
            Issue snapshot unavailable
          </h2>
          <p class="error-copy">
            <strong><%= @payload.error.code %>:</strong> <%= @payload.error.message %>
          </p>
        </section>
      <% else %>
        <section class="metric-grid">
          <article class="metric-card">
            <p class="metric-label">Status</p>
            <p class="metric-value"><%= @payload.status %></p>
            <p class="metric-detail">Current orchestrator issue state.</p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Attempt</p>
            <p class="metric-value numeric"><%= issue_attempt(@payload) %></p>
            <p class="metric-detail">Current retry attempt, including active retry entries.</p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Session</p>
            <p class="metric-value mono"><%= issue_session_id(@payload) || "n/a" %></p>
            <p class="metric-detail">Current agent session identifier for this issue.</p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Run</p>
            <p class="metric-value mono"><%= issue_run_id(@payload) || "n/a" %></p>
            <p class="metric-detail">Stable orchestration run identifier.</p>
          </article>
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Workspace</h2>
              <p class="section-copy">Current resolved workspace and host projection.</p>
            </div>
          </div>

          <pre class="code-panel"><%= pretty_value(@payload.workspace) %></pre>
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Dynamic tools</h2>
              <p class="section-copy">Issue-scoped workflow tool usage.</p>
            </div>
          </div>

          <div class="metric-grid">
            <article class="metric-card">
              <p class="metric-label">Typed hits</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.typed_tool_hits()) %></p>
              <p class="metric-detail">Successful typed workflow tool executions.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Raw attempts</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.raw_tool_attempts()) %></p>
              <p class="metric-detail">Rejected or failed raw tool attempts.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Fallback</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.fallback_count()) %></p>
              <p class="metric-detail">Operator migration fallback calls.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Unsupported</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.unsupported_tool_count()) %></p>
              <p class="metric-detail">Calls blocked before source execution.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Unavailable</p>
              <p class="metric-value numeric"><%= dynamic_tool_metric(@payload, DynamicToolMetrics.provider_capability_unavailable_count()) %></p>
              <p class="metric-detail">Provider capabilities reported as unavailable.</p>
            </article>
          </div>

          <.dynamic_tool_alerts payload={@payload} />
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Recent structured events</h2>
              <p class="section-copy">Bounded issue/run/session-correlated events from the shared in-memory store.</p>
            </div>
          </div>

          <%= if Map.get(@payload, :recent_events, []) == [] do %>
            <p class="empty-state">No issue-scoped structured events captured yet.</p>
          <% else %>
            <div class="table-wrap">
              <table class="data-table" style="min-width: 960px;">
                <thead>
                  <tr>
                    <th>When</th>
                    <th>Event</th>
                    <th>Component</th>
                    <th>Session / turn</th>
                    <th>Message</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={event <- Map.get(@payload, :recent_events, [])}>
                    <td class="mono"><%= event["timestamp"] || "n/a" %></td>
                    <td class="mono"><%= event["event"] || "n/a" %></td>
                    <td class="mono"><%= event["component"] || "n/a" %></td>
                    <td>
                      <div class="detail-stack">
                        <span class="mono"><%= event["session_id"] || "n/a" %></span>
                        <span class="muted mono"><%= event["turn_id"] || event["run_id"] || "n/a" %></span>
                      </div>
                    </td>
                    <td>
                      <div class="detail-stack">
                        <span class="event-text" title={event["message"] || "n/a"}>
                          <%= event["message"] || "n/a" %>
                        </span>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <section class="section-card">
          <div class="section-header">
            <div>
              <h2 class="section-title">Agent session logs</h2>
              <p class="section-copy">Chronological structured agent and tool-call lifecycle logs for this issue.</p>
            </div>
          </div>

          <%= if get_in(@payload, [:logs, :agent_session_logs]) in [nil, []] do %>
            <p class="empty-state">No structured agent session logs captured yet.</p>
          <% else %>
            <div class="table-wrap">
              <table class="data-table" style="min-width: 980px;">
                <thead>
                  <tr>
                    <th>When</th>
                    <th>Event</th>
                    <th>Component</th>
                    <th>Context</th>
                    <th>Message</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={event <- get_in(@payload, [:logs, :agent_session_logs])}>
                    <td class="mono"><%= event["timestamp"] || "n/a" %></td>
                    <td class="mono"><%= event["event"] || "n/a" %></td>
                    <td class="mono"><%= event["component"] || "n/a" %></td>
                    <td>
                      <div class="detail-stack">
                        <span class="mono"><%= event["session_id"] || event["thread_id"] || "n/a" %></span>
                        <span class="muted mono"><%= event["turn_id"] || event["tool_name"] || event["run_id"] || "n/a" %></span>
                      </div>
                    </td>
                    <td>
                      <div class="detail-stack">
                        <span class="event-text" title={event["message"] || "n/a"}>
                          <%= event["message"] || "n/a" %>
                        </span>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>
      <% end %>
    </section>
    """
  end

  defp load_payload(live_action, issue_identifier, context)
       when live_action in [:index, :issue] and context in [:mount, :params, :refresh] do
    case live_action do
      :issue -> load_issue_payload(issue_identifier)
      _ -> Presenter.state_payload(orchestrator(), snapshot_timeout_ms())
    end
  rescue
    error ->
      formatted_error = Exception.format_banner(:error, error)

      emit_dashboard_live_event(
        :warning,
        :dashboard_live_payload_load_failed,
        %{
          issue_identifier: issue_identifier,
          error: formatted_error,
          result_summary: "context=#{context} live_action=#{live_action}",
          message: "dashboard_live_payload_load_failed context=#{context} live_action=#{live_action}#{issue_identifier_suffix(issue_identifier)} error=#{formatted_error}"
        }
      )

      payload_load_error_payload(live_action, issue_identifier)
  catch
    kind, reason ->
      formatted_error = Exception.format_banner(kind, reason)

      emit_dashboard_live_event(
        :warning,
        :dashboard_live_payload_load_failed,
        %{
          issue_identifier: issue_identifier,
          error: formatted_error,
          result_summary: "context=#{context} live_action=#{live_action}",
          message: "dashboard_live_payload_load_failed context=#{context} live_action=#{live_action}#{issue_identifier_suffix(issue_identifier)} error=#{formatted_error}"
        }
      )

      payload_load_error_payload(live_action, issue_identifier)
  end

  defp load_issue_payload(issue_identifier)
       when is_binary(issue_identifier) and issue_identifier != "" do
    case Presenter.issue_payload(issue_identifier, orchestrator(), snapshot_timeout_ms()) do
      {:ok, payload} -> payload
      {:error, :issue_not_found} -> issue_not_found_payload(issue_identifier)
    end
  end

  defp load_issue_payload(_issue_identifier), do: issue_not_found_payload(nil)

  defp orchestrator do
    RuntimeConfig.orchestrator()
  end

  defp snapshot_timeout_ms do
    RuntimeConfig.snapshot_timeout_ms()
  end

  defp completed_runtime_seconds(payload) do
    Map.get(agent_totals(payload), :seconds_running, 0) || 0
  end

  defp agent_totals(payload) do
    Map.get(payload, :agent_totals) || %{}
  end

  defp agent_rate_limits(payload) do
    Map.get(payload, :agent_rate_limits)
  end

  defp dynamic_tool_metric(payload, key) when is_map(payload) and is_binary(key) do
    payload
    |> Map.get(:dynamic_tool_metrics, %{})
    |> Map.get(key, 0)
    |> format_int()
  end

  defp dynamic_tool_alerts(assigns) do
    ~H"""
    <div class="detail-stack" style="margin-top: 1rem;">
      <p class="metric-label">Operator alerts</p>

      <%= if dynamic_tool_operator_alerts(@payload) == [] do %>
        <p class="empty-state">No dynamic tool operator alerts.</p>
      <% else %>
        <article
          :for={alert <- dynamic_tool_operator_alerts(@payload)}
          class={"metric-card " <> dynamic_tool_alert_class(alert)}
        >
          <p class="metric-label"><%= dynamic_tool_alert_severity(alert) %> · <%= dynamic_tool_alert_category(alert) %></p>
          <p class="metric-detail"><%= dynamic_tool_alert_message(alert) %></p>
          <p :if={dynamic_tool_alert_capabilities(alert) != []} class="metric-detail mono">
            capabilities=<%= Enum.join(dynamic_tool_alert_capabilities(alert), ", ") %>
          </p>
          <p class="metric-detail mono">count=<%= dynamic_tool_alert_count(alert) %> metric=<%= dynamic_tool_alert_metric(alert) %></p>
        </article>
      <% end %>
    </div>
    """
  end

  defp dynamic_tool_operator_alerts(payload) when is_map(payload) do
    payload
    |> Map.get(:dynamic_tool_metrics, %{})
    |> Map.get(DynamicToolMetrics.operator_alerts(), [])
    |> case do
      alerts when is_list(alerts) -> alerts
      _alerts -> []
    end
  end

  defp dynamic_tool_alert_class(%{} = alert) do
    case AlertContract.severity(alert) do
      @alert_critical -> "status-card-danger"
      @alert_warning -> "status-card-warning"
      _severity -> "status-card-info"
    end
  end

  defp dynamic_tool_alert_capabilities(alert), do: AlertContract.capabilities(alert)

  defp dynamic_tool_alert_severity(alert), do: AlertContract.severity(alert)

  defp dynamic_tool_alert_category(%{} = alert),
    do: alert[@alert_category_key] || AlertContract.default_category()

  defp dynamic_tool_alert_category(_alert), do: AlertContract.default_category()

  defp dynamic_tool_alert_message(%{} = alert),
    do: alert[@alert_message_key] || alert[@alert_code_key] || AlertContract.default_message()

  defp dynamic_tool_alert_message(_alert), do: AlertContract.default_message()

  defp dynamic_tool_alert_count(%{} = alert), do: alert[@alert_count_key] || 0
  defp dynamic_tool_alert_count(_alert), do: 0

  defp dynamic_tool_alert_metric(%{} = alert), do: alert[@alert_metric_key] || "n/a"
  defp dynamic_tool_alert_metric(_alert), do: "n/a"

  defp total_runtime_seconds(payload, now) do
    completed_runtime_seconds(payload) +
      Enum.reduce(payload.running, 0, fn entry, total ->
        total + runtime_seconds_from_started_at(entry.started_at, now)
      end)
  end

  defp format_runtime_and_turns(started_at, turn_count, now)
       when is_integer(turn_count) and turn_count > 0 do
    "#{format_runtime_seconds(runtime_seconds_from_started_at(started_at, now))} / #{turn_count}"
  end

  defp format_runtime_and_turns(started_at, _turn_count, now),
    do: format_runtime_seconds(runtime_seconds_from_started_at(started_at, now))

  defp format_runtime_seconds(seconds) when is_number(seconds) do
    whole_seconds = max(trunc(seconds), 0)
    mins = div(whole_seconds, 60)
    secs = rem(whole_seconds, 60)
    "#{mins}m #{secs}s"
  end

  defp runtime_seconds_from_started_at(%DateTime{} = started_at, %DateTime{} = now) do
    DateTime.diff(now, started_at, :second)
  end

  defp runtime_seconds_from_started_at(started_at, %DateTime{} = now)
       when is_binary(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, parsed, _offset} -> runtime_seconds_from_started_at(parsed, now)
      _ -> 0
    end
  end

  defp runtime_seconds_from_started_at(_started_at, _now), do: 0

  defp format_int(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  defp format_int(_value), do: "n/a"

  defp issue_attempt(payload) when is_map(payload) do
    payload
    |> get_in([:attempts, :current_retry_attempt])
    |> case do
      attempt when is_integer(attempt) -> attempt
      _ -> 0
    end
  end

  defp issue_session_id(payload) when is_map(payload) do
    get_in(payload, [:running, :session_id])
  end

  defp issue_run_id(payload) when is_map(payload) do
    get_in(payload, [:running, :run_id]) || get_in(payload, [:retry, :run_id])
  end

  defp event_issue_label(%{"issue_identifier" => issue_identifier})
       when is_binary(issue_identifier),
       do: issue_identifier

  defp event_issue_label(%{"issue_id" => issue_id}) when is_binary(issue_id), do: issue_id
  defp event_issue_label(_event), do: "system"

  defp issue_live_path(issue_identifier) when is_binary(issue_identifier),
    do: BrowserPaths.issue_path(issue_identifier)

  defp state_badge_class(state) do
    Status.badge_class(state)
  end

  defp schedule_runtime_tick do
    Process.send_after(self(), :runtime_tick, @runtime_tick_ms)
  end

  defp emit_dashboard_live_event(level, event, fields) when is_map(fields) do
    ObservabilityLogger.emit(
      level,
      event,
      Map.put_new(fields, :component, "dashboard.live")
    )
  end

  defp payload_load_error_payload(:issue, issue_identifier) do
    %{
      issue_identifier: issue_identifier,
      error: %{
        code: "issue_projection_failed",
        message: "Issue dashboard projection failed"
      }
    }
  end

  defp payload_load_error_payload(_live_action, _issue_identifier) do
    %{
      generated_at: DateTime.utc_now(:second) |> DateTime.to_iso8601(),
      error: %{
        code: "snapshot_projection_failed",
        message: "Dashboard snapshot projection failed"
      }
    }
  end

  defp issue_not_found_payload(issue_identifier) do
    %{
      issue_identifier: issue_identifier,
      error: %{
        code: "issue_not_found",
        message: "Issue not found"
      }
    }
  end

  defp issue_identifier_suffix(issue_identifier)
       when is_binary(issue_identifier) and issue_identifier != "" do
    " issue_identifier=#{issue_identifier}"
  end

  defp issue_identifier_suffix(_issue_identifier), do: ""

  defp subscription_summary(:ok), do: "ok"
  defp subscription_summary(:skipped), do: "skipped"
  defp subscription_summary({:error, _reason}), do: "error"
  defp pretty_value(nil), do: "n/a"
  defp pretty_value(value), do: inspect(value, pretty: true, limit: :infinity)
end
