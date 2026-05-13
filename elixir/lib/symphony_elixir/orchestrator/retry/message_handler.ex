defmodule SymphonyElixir.Orchestrator.Retry.MessageHandler do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Retry.{Events, IssueHandler, Scheduler}

  @spec handle(map(), String.t(), reference(), keyword()) :: {:noreply, map()}
  def handle(state, issue_id, retry_token, opts)
      when is_map(state) and is_binary(issue_id) and is_reference(retry_token) do
    result =
      case Scheduler.pop_attempt_state(state, issue_id, retry_token) do
        {:ok, attempt, metadata, state} ->
          Events.started(state, issue_id, attempt, metadata, emit_event: Keyword.get(opts, :emit_event))

          IssueHandler.handle(
            state,
            issue_id,
            attempt,
            metadata,
            retry_issue_opts(state, metadata, opts)
          )

        {:stale, metadata, state} ->
          Events.cancelled(
            state,
            issue_id,
            metadata,
            "stale_retry_token",
            emit_event: Keyword.get(opts, :emit_event)
          )

          {:noreply, state}

        :missing ->
          {:noreply, state}
      end

    notify_dashboard(opts)
    result
  end

  def handle(state, _issue_id, _retry_token, opts) do
    notify_dashboard(opts)
    {:noreply, state}
  end

  defp retry_issue_opts(state, metadata, opts) do
    case Keyword.get(opts, :retry_issue_opts) do
      retry_issue_opts when is_function(retry_issue_opts, 2) -> retry_issue_opts.(state, metadata)
      _other -> []
    end
  end

  defp notify_dashboard(opts) do
    case Keyword.get(opts, :notify_dashboard) do
      notify_dashboard when is_function(notify_dashboard, 0) -> notify_dashboard.()
      _other -> :ok
    end
  end
end
