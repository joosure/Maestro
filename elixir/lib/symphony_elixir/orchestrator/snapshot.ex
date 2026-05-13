defmodule SymphonyElixir.Orchestrator.Snapshot do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.AgentUsage

  def build(state, opts \\ [])

  @spec build(map(), keyword()) :: map()
  def build(state, opts) when is_map(state) and is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    now_ms = Keyword.get(opts, :now_ms, System.monotonic_time(:millisecond))
    running_seconds = Keyword.get(opts, :running_seconds, &AgentUsage.running_seconds/2)

    %{
      running: running_entries(state, now, running_seconds),
      retrying: retry_entries(state, now_ms),
      agent_totals: Map.get(state, :agent_totals),
      agent_rate_limits: Map.get(state, :agent_rate_limits),
      polling: %{
        checking?: Map.get(state, :poll_check_in_progress) == true,
        next_poll_in_ms: next_poll_in_ms(Map.get(state, :next_poll_due_at_ms), now_ms),
        poll_interval_ms: Map.get(state, :poll_interval_ms)
      }
    }
  end

  def build(state, _opts), do: state

  defp running_entries(state, now, running_seconds) do
    running_entries = Map.get(state, :running, %{})

    Enum.map(running_entries, fn {issue_id, metadata} ->
      %{
        issue_id: issue_id,
        identifier: Map.get(metadata, :identifier),
        run_id: Map.get(metadata, :run_id),
        attempt: Map.get(metadata, :retry_attempt),
        state: issue_state(metadata),
        worker_host: Map.get(metadata, :worker_host),
        workspace_path: Map.get(metadata, :workspace_path),
        failure_class: Map.get(metadata, :failure_class),
        session_id: Map.get(metadata, :session_id),
        agent_provider_kind: Map.get(metadata, :agent_provider_kind),
        agent_process_pid: Map.get(metadata, :agent_process_pid),
        agent_input_tokens: Map.get(metadata, :agent_input_tokens),
        agent_output_tokens: Map.get(metadata, :agent_output_tokens),
        agent_total_tokens: Map.get(metadata, :agent_total_tokens),
        turn_count: Map.get(metadata, :turn_count, 0),
        started_at: Map.get(metadata, :started_at),
        last_agent_timestamp: Map.get(metadata, :last_agent_timestamp),
        last_agent_message: Map.get(metadata, :last_agent_message),
        last_agent_event: Map.get(metadata, :last_agent_event),
        runtime_seconds: running_seconds.(Map.get(metadata, :started_at), now)
      }
    end)
  end

  defp retry_entries(state, now_ms) do
    retry_attempts = Map.get(state, :retry_attempts, %{})

    retry_attempts
    |> Enum.reject(fn {_issue_id, retry} -> continuation_retry?(retry) end)
    |> Enum.map(fn {issue_id, %{attempt: attempt, due_at_ms: due_at_ms} = retry} ->
      %{
        issue_id: issue_id,
        attempt: attempt,
        run_id: Map.get(retry, :run_id),
        agent_provider_kind: Map.get(retry, :agent_provider_kind),
        due_in_ms: max(0, due_at_ms - now_ms),
        identifier: Map.get(retry, :identifier),
        error: Map.get(retry, :error),
        worker_host: Map.get(retry, :worker_host),
        workspace_path: Map.get(retry, :workspace_path),
        failure_class: Map.get(retry, :failure_class)
      }
    end)
  end

  defp continuation_retry?(%{delay_type: :continuation}), do: true
  defp continuation_retry?(_retry), do: false

  defp issue_state(%{issue: issue}) when is_map(issue), do: Map.get(issue, :state)
  defp issue_state(_metadata), do: nil

  defp next_poll_in_ms(nil, _now_ms), do: nil

  defp next_poll_in_ms(next_poll_due_at_ms, now_ms) when is_integer(next_poll_due_at_ms) do
    max(0, next_poll_due_at_ms - now_ms)
  end
end
