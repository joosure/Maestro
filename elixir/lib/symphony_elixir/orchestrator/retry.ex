defmodule SymphonyElixir.Orchestrator.Retry do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Retry.{MessageHandler, Scheduler}

  def schedule(state, issue_id, attempt, metadata, opts \\ [])

  @spec schedule(map(), String.t(), integer() | nil, map(), keyword()) :: map()
  def schedule(state, issue_id, attempt, metadata, opts), do: Scheduler.schedule(state, issue_id, attempt, metadata, opts)

  def handle_timer_message(state, issue_id, retry_token, opts \\ [])

  @spec handle_timer_message(map(), String.t(), reference(), keyword()) :: {:noreply, map()}
  def handle_timer_message(state, issue_id, retry_token, opts),
    do: MessageHandler.handle(state, issue_id, retry_token, opts)

  @spec normalize_attempt(term()) :: non_neg_integer()
  def normalize_attempt(attempt), do: Scheduler.normalize_attempt(attempt)

  @spec next_attempt_from_running(map()) :: integer() | nil
  def next_attempt_from_running(running_entry), do: Scheduler.next_attempt_from_running(running_entry)
end
