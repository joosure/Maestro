defmodule SymphonyElixirWeb.Presenter do
  @moduledoc """
  Shared projections for the observability API and dashboard.
  """

  alias SymphonyElixir.{AgentProvider, Config, Orchestrator}
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Observability.StatusDashboard

  @spec state_payload(GenServer.name(), timeout()) :: map()
  def state_payload(orchestrator, snapshot_timeout_ms) do
    generated_at = DateTime.utc_now(:second) |> DateTime.to_iso8601()

    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        %{
          generated_at: generated_at,
          counts: %{
            running: length(snapshot.running),
            retrying: length(snapshot.retrying)
          },
          running: Enum.map(snapshot.running, &running_entry_payload/1),
          retrying: Enum.map(snapshot.retrying, &retry_entry_payload/1),
          agent_totals: Map.get(snapshot, :agent_totals),
          agent_rate_limits: Map.get(snapshot, :agent_rate_limits),
          dynamic_tool_metrics: EventStore.dynamic_tool_usage_metrics(limit: 1_000),
          recent_events: EventStore.recent_events(limit: 20)
        }

      :timeout ->
        %{generated_at: generated_at, error: %{code: "snapshot_timeout", message: "Snapshot timed out"}}

      :unavailable ->
        %{generated_at: generated_at, error: %{code: "snapshot_unavailable", message: "Snapshot unavailable"}}
    end
  end

  @spec issue_payload(String.t(), GenServer.name(), timeout()) :: {:ok, map()} | {:error, :issue_not_found}
  def issue_payload(issue_identifier, orchestrator, snapshot_timeout_ms) when is_binary(issue_identifier) do
    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        running = Enum.find(snapshot.running, &(&1.identifier == issue_identifier))
        retry = Enum.find(snapshot.retrying, &(&1.identifier == issue_identifier))

        if is_nil(running) and is_nil(retry) do
          {:error, :issue_not_found}
        else
          {:ok, issue_payload_body(issue_identifier, running, retry)}
        end

      _ ->
        {:error, :issue_not_found}
    end
  end

  @spec refresh_payload(GenServer.name()) :: {:ok, map()} | {:error, :unavailable}
  def refresh_payload(orchestrator) do
    case Orchestrator.request_refresh(orchestrator) do
      :unavailable ->
        {:error, :unavailable}

      payload ->
        {:ok, Map.update!(payload, :requested_at, &DateTime.to_iso8601/1)}
    end
  end

  defp issue_payload_body(issue_identifier, running, retry) do
    %{
      issue_identifier: issue_identifier,
      issue_id: issue_id_from_entries(running, retry),
      status: issue_status(running, retry),
      workspace: %{
        path: workspace_path(issue_identifier, running, retry),
        host: workspace_host(running, retry)
      },
      attempts: %{
        restart_count: restart_count(retry),
        current_retry_attempt: retry_attempt(retry)
      },
      agent: agent_status_payload(running, retry),
      turn: turn_status_payload(running, retry),
      provider: provider_status_payload(running, retry),
      worker: worker_status_payload(running, retry),
      running: running && running_issue_payload(running),
      retry: retry && retry_issue_payload(retry),
      logs: %{
        agent_session_logs: agent_session_logs_payload(running, retry, issue_identifier)
      },
      dynamic_tool_metrics: dynamic_tool_metrics_payload(running, retry, issue_identifier),
      recent_events: recent_events_payload(running, retry, issue_identifier),
      last_error: retry && retry.error,
      tracked: %{}
    }
  end

  defp issue_id_from_entries(running, retry),
    do: (running && running.issue_id) || (retry && retry.issue_id)

  defp restart_count(retry), do: max(retry_attempt(retry) - 1, 0)
  defp retry_attempt(nil), do: 0
  defp retry_attempt(retry), do: retry.attempt || 0

  defp issue_status(_running, nil), do: "running"
  defp issue_status(nil, _retry), do: "retrying"
  defp issue_status(_running, _retry), do: "running"

  defp running_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      run_id: Map.get(entry, :run_id),
      state: entry.state,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      session_id: entry.session_id,
      turn_count: Map.get(entry, :turn_count, 0),
      turn: turn_status_payload(entry, nil),
      provider: provider_status_payload(entry, nil),
      worker: worker_status_payload(entry, nil),
      agent: agent_payload(entry),
      last_event: agent_last_event(entry),
      last_message: summarize_message(agent_last_message(entry)),
      started_at: iso8601(entry.started_at),
      last_event_at: iso8601(agent_last_timestamp(entry)),
      tokens: agent_tokens_payload(entry)
    }
    |> maybe_put(:failure_class, Map.get(entry, :failure_class))
  end

  defp retry_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      attempt: entry.attempt,
      run_id: Map.get(entry, :run_id),
      due_at: due_at_iso8601(entry.due_in_ms),
      error: entry.error,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      agent: agent_status_payload(nil, entry),
      provider: provider_status_payload(nil, entry),
      worker: worker_status_payload(nil, entry)
    }
    |> maybe_put(:failure_class, Map.get(entry, :failure_class))
  end

  defp running_issue_payload(running) do
    %{
      worker_host: Map.get(running, :worker_host),
      workspace_path: Map.get(running, :workspace_path),
      run_id: Map.get(running, :run_id),
      session_id: running.session_id,
      turn_count: Map.get(running, :turn_count, 0),
      state: running.state,
      turn: turn_status_payload(running, nil),
      provider: provider_status_payload(running, nil),
      worker: worker_status_payload(running, nil),
      started_at: iso8601(running.started_at),
      agent: agent_payload(running),
      last_event: agent_last_event(running),
      last_message: summarize_message(agent_last_message(running)),
      last_event_at: iso8601(agent_last_timestamp(running)),
      tokens: agent_tokens_payload(running)
    }
    |> maybe_put(:failure_class, Map.get(running, :failure_class))
  end

  defp retry_issue_payload(retry) do
    %{
      attempt: retry.attempt,
      run_id: Map.get(retry, :run_id),
      due_at: due_at_iso8601(retry.due_in_ms),
      error: retry.error,
      worker_host: Map.get(retry, :worker_host),
      workspace_path: Map.get(retry, :workspace_path),
      agent: agent_status_payload(nil, retry),
      provider: provider_status_payload(nil, retry),
      worker: worker_status_payload(nil, retry)
    }
    |> maybe_put(:failure_class, Map.get(retry, :failure_class))
  end

  defp workspace_path(issue_identifier, running, retry) do
    (running && Map.get(running, :workspace_path)) ||
      (retry && Map.get(retry, :workspace_path)) ||
      Path.join(Config.settings!().workspace.root, issue_identifier)
  end

  defp workspace_host(running, retry) do
    (running && Map.get(running, :worker_host)) || (retry && Map.get(retry, :worker_host))
  end

  defp recent_events_payload(running, retry, issue_identifier) do
    issue_event_context(running, retry, issue_identifier)
    |> EventStore.recent_issue_events()
  end

  defp agent_session_logs_payload(running, retry, issue_identifier) do
    issue_event_context(running, retry, issue_identifier)
    |> EventStore.agent_session_logs()
  end

  defp dynamic_tool_metrics_payload(running, retry, issue_identifier) do
    EventStore.dynamic_tool_usage_metrics(
      context: issue_event_context(running, retry, issue_identifier),
      limit: 1_000
    )
  end

  defp issue_event_context(running, retry, issue_identifier) do
    %{
      issue_id: issue_id_from_entries(running, retry),
      issue_identifier: issue_identifier,
      run_id: (running && Map.get(running, :run_id)) || (retry && Map.get(retry, :run_id)),
      session_id: running && Map.get(running, :session_id)
    }
  end

  defp agent_payload(entry) do
    %{
      provider_kind: agent_provider_kind(entry),
      process_pid: agent_process_pid(entry),
      last_event: agent_last_event(entry),
      last_message: summarize_message(agent_last_message(entry)),
      last_event_at: iso8601(agent_last_timestamp(entry)),
      tokens: agent_tokens_payload(entry)
    }
  end

  defp agent_status_payload(running, retry) do
    entry = running || retry

    %{
      run_id: entry && Map.get(entry, :run_id),
      status: agent_status(running, retry),
      attempt: agent_attempt(running, retry),
      started_at: running && iso8601(Map.get(running, :started_at)),
      updated_at: running && iso8601(agent_last_timestamp(running)),
      duration_ms: running_duration_ms(running),
      terminal_reason: retry && Map.get(retry, :error)
    }
  end

  defp turn_status_payload(running, retry) do
    %{
      turn_number: running && Map.get(running, :turn_count, 0),
      max_turns: Config.settings!().agent.execution.max_turns,
      status: turn_status(running, retry),
      started_at: nil,
      updated_at: running && iso8601(agent_last_timestamp(running)),
      duration_ms: nil,
      error_code: nil
    }
  end

  defp provider_status_payload(running, retry) do
    entry = running || retry
    kind = entry && agent_provider_kind(entry)

    %{
      kind: kind,
      capabilities: provider_capabilities(kind),
      session_id: entry && Map.get(entry, :session_id),
      thread_id: nil,
      turn_id: nil,
      stateful: provider_stateful?(kind)
    }
  end

  defp worker_status_payload(running, retry) do
    entry = running || retry

    %{
      host: entry && Map.get(entry, :worker_host),
      workspace_path: entry && Map.get(entry, :workspace_path),
      status: worker_status(running, retry)
    }
  end

  defp agent_status(running, _retry) when not is_nil(running), do: "running"
  defp agent_status(nil, retry) when not is_nil(retry), do: "retry_scheduled"
  defp agent_status(_running, _retry), do: "unknown"

  defp turn_status(running, _retry) when not is_nil(running), do: "running"
  defp turn_status(nil, retry) when not is_nil(retry), do: "retry_scheduled"
  defp turn_status(_running, _retry), do: "unknown"

  defp worker_status(running, _retry) when not is_nil(running), do: "running"
  defp worker_status(nil, retry) when not is_nil(retry), do: "retry_scheduled"
  defp worker_status(_running, _retry), do: "unknown"

  defp agent_attempt(running, _retry) when not is_nil(running), do: Map.get(running, :attempt)
  defp agent_attempt(nil, retry) when not is_nil(retry), do: Map.get(retry, :attempt)
  defp agent_attempt(_running, _retry), do: nil

  defp running_duration_ms(nil), do: nil

  defp running_duration_ms(running) do
    case Map.get(running, :runtime_seconds) do
      seconds when is_integer(seconds) -> seconds * 1_000
      _ -> nil
    end
  end

  defp provider_capabilities(kind) when is_binary(kind) do
    AgentProvider.capabilities(kind: kind)
  rescue
    _ -> []
  end

  defp provider_capabilities(_kind), do: []

  defp provider_stateful?(kind) when is_binary(kind) do
    AgentProvider.supports?("agent.session.stateful", kind: kind)
  rescue
    _ -> false
  end

  defp provider_stateful?(_kind), do: false

  defp agent_provider_kind(entry), do: Map.get(entry, :agent_provider_kind)
  defp agent_process_pid(entry), do: Map.get(entry, :agent_process_pid)
  defp agent_last_event(entry), do: Map.get(entry, :last_agent_event)
  defp agent_last_message(entry), do: Map.get(entry, :last_agent_message)
  defp agent_last_timestamp(entry), do: Map.get(entry, :last_agent_timestamp)

  defp agent_tokens_payload(entry) do
    %{
      input_tokens: Map.get(entry, :agent_input_tokens),
      output_tokens: Map.get(entry, :agent_output_tokens),
      total_tokens: Map.get(entry, :agent_total_tokens)
    }
  end

  defp summarize_message(nil), do: nil
  defp summarize_message(message), do: StatusDashboard.present_agent_message(message)

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp due_at_iso8601(due_in_ms) when is_integer(due_in_ms) do
    DateTime.utc_now()
    |> DateTime.add(div(due_in_ms, 1_000), :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp due_at_iso8601(_due_in_ms), do: nil

  defp iso8601(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp iso8601(_datetime), do: nil
end
