defmodule SymphonyElixir.Orchestrator.Retry.Events do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Retry.ResultSummary
  alias SymphonyElixir.Orchestrator.Retry.Status

  @spec scheduled(term(), map(), map(), map(), integer(), String.t()) :: :ok
  def scheduled(emit_event, state, metadata, retry_entry, delay_ms, issue_id)
      when is_map(state) and is_map(metadata) and is_map(retry_entry) and is_integer(delay_ms) and
             is_binary(issue_id) do
    emit(
      emit_event,
      :warning,
      :issue_retry_scheduled,
      nil,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: retry_entry.identifier,
        attempt: retry_entry.attempt,
        run_id: retry_entry.run_id,
        duration_ms: delay_ms,
        error: retry_entry.error,
        agent_provider_kind: retry_entry.agent_provider_kind,
        worker_host: retry_entry.worker_host,
        workspace_path: retry_entry.workspace_path,
        failure_class: retry_entry.failure_class
      }
    )

    agent_run_scheduled(emit_event, state, metadata, retry_entry, delay_ms, issue_id)
  end

  def scheduled(_emit_event, _state, _metadata, _retry_entry, _delay_ms, _issue_id), do: :ok

  @spec started(map(), String.t(), integer(), map(), keyword()) :: :ok
  def started(state, issue_id, attempt, metadata, opts)
      when is_binary(issue_id) and is_integer(attempt) and is_map(metadata) do
    emit(
      Keyword.get(opts, :emit_event),
      :info,
      :issue_retry_started,
      nil,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: metadata[:identifier] || issue_id,
        attempt: attempt,
        run_id: metadata[:run_id],
        agent_provider_kind: metadata[:agent_provider_kind],
        error: metadata[:error],
        worker_host: metadata[:worker_host],
        workspace_path: metadata[:workspace_path],
        failure_class: metadata[:failure_class],
        result_summary: ResultSummary.retry_started(),
        message: "issue_retry_started issue_id=#{issue_id} issue_identifier=#{metadata[:identifier] || issue_id} attempt=#{attempt}"
      }
    )
  end

  def started(_state, _issue_id, _attempt, _metadata, _opts), do: :ok

  @spec cancelled(map(), String.t(), map(), String.t(), keyword()) :: :ok
  def cancelled(state, issue_id, metadata, cancel_reason, opts)
      when is_binary(issue_id) and is_map(metadata) and is_binary(cancel_reason) do
    emit(
      Keyword.get(opts, :emit_event),
      :info,
      :issue_retry_cancelled,
      nil,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: metadata[:identifier] || issue_id,
        attempt: metadata[:attempt],
        run_id: metadata[:run_id],
        agent_provider_kind: metadata[:agent_provider_kind],
        error: metadata[:error],
        worker_host: metadata[:worker_host],
        workspace_path: metadata[:workspace_path],
        failure_class: metadata[:failure_class],
        skip_reason: cancel_reason,
        result_summary: ResultSummary.retry_cancelled(),
        message: "issue_retry_cancelled issue_id=#{issue_id} issue_identifier=#{metadata[:identifier] || issue_id} attempt=#{metadata[:attempt]} reason=#{cancel_reason}"
      }
    )
  end

  def cancelled(_state, _issue_id, _metadata, _cancel_reason, _opts), do: :ok

  @spec released(term(), term(), map(), integer() | nil, map(), String.t()) :: :ok
  def released(emit_event, issue, state, attempt, metadata, skip_reason)
      when is_map(state) and is_map(metadata) and is_binary(skip_reason) do
    emit(
      emit_event,
      :info,
      :issue_retry_released,
      issue,
      state,
      %{
        attempt: attempt,
        skip_reason: skip_reason,
        run_id: metadata[:run_id],
        worker_host: metadata[:worker_host],
        workspace_path: metadata[:workspace_path]
      }
    )
  end

  def released(_emit_event, _issue, _state, _attempt, _metadata, _skip_reason), do: :ok

  @spec emit(term(), atom(), atom(), term(), map(), map()) :: :ok
  def emit(emit_event, level, event, issue, state, extra_fields)
      when is_function(emit_event, 5) and is_map(extra_fields) do
    emit_event.(level, event, issue, state, extra_fields)
  end

  def emit(_emit_event, _level, _event, _issue, _state, _extra_fields), do: :ok

  defp agent_run_scheduled(_emit_event, _state, %{delay_type: :continuation}, _retry_entry, _delay_ms, _issue_id),
    do: :ok

  defp agent_run_scheduled(emit_event, state, _metadata, retry_entry, delay_ms, issue_id) do
    emit(
      emit_event,
      :warning,
      :agent_run_retry_scheduled,
      nil,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: retry_entry.identifier,
        attempt: retry_entry.attempt,
        run_id: retry_entry.run_id,
        duration_ms: delay_ms,
        retry_delay_ms: delay_ms,
        retry_policy: "orchestrator_backoff",
        status: Status.retry_scheduled(),
        result_summary: ResultSummary.retry_scheduled(),
        error: retry_entry.error,
        agent_provider_kind: retry_entry.agent_provider_kind,
        worker_host: retry_entry.worker_host,
        workspace_path: retry_entry.workspace_path,
        failure_class: retry_entry.failure_class || "agent_run_failure"
      }
    )
  end
end
