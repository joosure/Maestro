defmodule SymphonyElixir.Orchestrator.Retry.Scheduler do
  @moduledoc false

  import Bitwise, only: [<<<: 2]

  alias SymphonyElixir.Config
  alias SymphonyElixir.Orchestrator.Retry.{Events, Metadata}

  @continuation_retry_delay_ms 1_000
  @failure_retry_base_ms 10_000

  @spec schedule(map(), String.t(), integer() | nil, map(), keyword()) :: map()
  def schedule(state, issue_id, attempt, metadata, opts)
      when is_map(state) and is_binary(issue_id) and is_map(metadata) do
    previous_retry = Map.get(attempts(state), issue_id, %{attempt: 0})
    next_attempt = if is_integer(attempt), do: attempt, else: previous_retry.attempt + 1
    delay_ms = retry_delay(next_attempt, metadata)
    retry_token = make_ref()
    due_at_ms = System.monotonic_time(:millisecond) + delay_ms

    cancel_timer(Map.get(previous_retry, :timer_ref))
    timer_ref = Process.send_after(self(), {:retry_issue, issue_id, retry_token}, delay_ms)

    retry_entry =
      Metadata.build_entry(
        issue_id,
        previous_retry,
        metadata,
        next_attempt,
        timer_ref,
        retry_token,
        due_at_ms
      )

    Events.scheduled(Keyword.get(opts, :emit_event), state, metadata, retry_entry, delay_ms, issue_id)

    put_attempts(state, Map.put(attempts(state), issue_id, retry_entry))
  end

  def schedule(state, _issue_id, _attempt, _metadata, _opts), do: state

  @spec pop_attempt_state(map(), String.t(), reference()) ::
          {:ok, integer(), map(), map()} | {:stale, map(), map()} | :missing
  def pop_attempt_state(state, issue_id, retry_token)
      when is_map(state) and is_binary(issue_id) and is_reference(retry_token) do
    case Map.get(attempts(state), issue_id) do
      %{attempt: attempt, retry_token: ^retry_token} = retry_entry ->
        metadata = Metadata.from_entry(retry_entry)
        {:ok, attempt, metadata, put_attempts(state, Map.delete(attempts(state), issue_id))}

      %{attempt: attempt} = retry_entry ->
        metadata = Map.put(Metadata.from_entry(retry_entry), :attempt, attempt)
        {:stale, metadata, state}

      _other ->
        :missing
    end
  end

  def pop_attempt_state(_state, _issue_id, _retry_token), do: :missing

  @spec normalize_attempt(term()) :: non_neg_integer()
  def normalize_attempt(attempt) when is_integer(attempt) and attempt > 0, do: attempt
  def normalize_attempt(_attempt), do: 0

  @spec next_attempt_from_running(map()) :: integer() | nil
  def next_attempt_from_running(running_entry) when is_map(running_entry) do
    case Map.get(running_entry, :retry_attempt) do
      attempt when is_integer(attempt) and attempt > 0 -> attempt + 1
      _other -> nil
    end
  end

  def next_attempt_from_running(_running_entry), do: nil

  defp retry_delay(attempt, metadata)
       when is_integer(attempt) and attempt > 0 and is_map(metadata) do
    if metadata[:delay_type] == :continuation and attempt == 1 do
      @continuation_retry_delay_ms
    else
      failure_retry_delay(attempt)
    end
  end

  defp failure_retry_delay(attempt) do
    max_delay_power = min(attempt - 1, 10)

    min(
      @failure_retry_base_ms * (1 <<< max_delay_power),
      Config.settings!().agent.execution.max_retry_backoff_ms
    )
  end

  defp cancel_timer(timer_ref) when is_reference(timer_ref), do: Process.cancel_timer(timer_ref)
  defp cancel_timer(_timer_ref), do: :ok

  defp attempts(%{retry_attempts: retry_attempts}) when is_map(retry_attempts), do: retry_attempts
  defp attempts(_state), do: %{}

  defp put_attempts(%{retry_attempts: _} = state, retry_attempts) when is_map(retry_attempts) do
    put_in(state.retry_attempts, retry_attempts)
  end

  defp put_attempts(state, _retry_attempts), do: state
end
