defmodule SymphonyElixir.Agent.Runner.TurnLoop do
  @moduledoc false

  alias SymphonyElixir.Agent.{Continuation, Credential}
  alias SymphonyElixir.Agent.Runner.{EventFields, Prompts, RunContext, TurnEvents, WorkerUpdates}
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @type worker_host :: String.t() | nil

  @spec run(
          term(),
          Path.t(),
          term(),
          term(),
          keyword(),
          ([String.t()] -> term()),
          worker_host(),
          String.t(),
          pos_integer(),
          pos_integer()
        ) :: :ok | {:error, term()}
  def run(
        app_session,
        workspace,
        issue,
        update_recipient,
        opts,
        issue_state_fetcher,
        worker_host,
        run_id,
        turn_number,
        max_turns
      ) do
    prompt = Prompts.build(app_session, issue, Keyword.put(opts, :run_id, run_id), turn_number, max_turns)
    turn_started_at_ms = RunContext.monotonic_ms()

    ObsLogger.emit(
      :info,
      :agent_turn_started,
      EventFields.turn(app_session, issue, worker_host, workspace, run_id, turn_number, max_turns, %{
        status: "started",
        operation: "run_turn"
      })
      |> Map.merge(EventFields.prompt_observability_fields(prompt))
    )

    case AgentProvider.run_turn(
           app_session,
           prompt,
           issue,
           on_message: WorkerUpdates.message_handler(update_recipient, issue)
         ) do
      {:ok, turn_session} ->
        handle_turn_result(
          turn_session,
          app_session,
          workspace,
          issue,
          update_recipient,
          opts,
          issue_state_fetcher,
          worker_host,
          run_id,
          turn_number,
          max_turns,
          turn_started_at_ms
        )

      {:error, reason} = error ->
        handle_turn_error(error, reason, app_session, workspace, issue, worker_host, run_id, turn_number, max_turns, turn_started_at_ms)
    end
  end

  defp handle_turn_result(
         turn_session,
         app_session,
         workspace,
         issue,
         update_recipient,
         opts,
         issue_state_fetcher,
         worker_host,
         run_id,
         turn_number,
         max_turns,
         turn_started_at_ms
       ) do
    Credential.record_session_usage(
      app_session,
      turn_result_value(turn_session, :usage),
      run_id: run_id,
      issue_id: Map.get(issue, :id),
      issue_identifier: Map.get(issue, :identifier)
    )

    turn_terminal_event =
      TurnEvents.terminal_event_for_status(turn_result_value(turn_session, :status))

    ObsLogger.emit(
      TurnEvents.terminal_level(turn_terminal_event),
      turn_terminal_event,
      EventFields.turn(
        app_session,
        issue,
        worker_host,
        workspace,
        run_id,
        turn_number,
        max_turns,
        %{
          status: TurnEvents.status_string(turn_result_value(turn_session, :status)),
          operation: "run_turn",
          duration_ms: RunContext.elapsed_ms(turn_started_at_ms),
          session_id: turn_result_value(turn_session, :session_id),
          thread_id: turn_result_value(turn_session, :thread_id),
          turn_id: turn_result_value(turn_session, :turn_id),
          usage: turn_result_value(turn_session, :usage)
        }
        |> Map.merge(TurnEvents.status_error_fields(turn_result_value(turn_session, :status)))
      )
    )

    if turn_result_value(turn_session, :status) == :completed do
      continue_after_completed_turn(
        turn_session,
        app_session,
        workspace,
        issue,
        update_recipient,
        opts,
        issue_state_fetcher,
        worker_host,
        run_id,
        turn_number,
        max_turns
      )
    else
      {:error, {:agent_turn_terminal_status, turn_result_value(turn_session, :status)}}
    end
  end

  defp continue_after_completed_turn(
         turn_session,
         app_session,
         workspace,
         issue,
         update_recipient,
         opts,
         issue_state_fetcher,
         worker_host,
         run_id,
         turn_number,
         max_turns
       ) do
    Credential.record_session_success(
      app_session,
      run_id: run_id,
      issue_id: Map.get(issue, :id),
      issue_identifier: Map.get(issue, :identifier)
    )

    case continue_with_issue?(
           issue,
           issue_state_fetcher,
           Keyword.merge(opts, run_id: run_id, worker_host: worker_host, workspace: workspace)
         ) do
      {:continue, refreshed_issue} when turn_number < max_turns ->
        emit_continuation_started(
          refreshed_issue,
          issue,
          worker_host,
          workspace,
          run_id,
          turn_number,
          turn_session
        )

        run(
          app_session,
          workspace,
          refreshed_issue,
          update_recipient,
          opts,
          issue_state_fetcher,
          worker_host,
          run_id,
          turn_number + 1,
          max_turns
        )

      {:continue, refreshed_issue} ->
        emit_max_turns_reached(refreshed_issue, worker_host, workspace, run_id, turn_number, turn_session)
        :ok

      {:done, _refreshed_issue} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_turn_error(
         error,
         reason,
         app_session,
         workspace,
         issue,
         worker_host,
         run_id,
         turn_number,
         max_turns,
         turn_started_at_ms
       ) do
    if Credential.Store.quota_error?(reason) do
      Credential.mark_session_quota_exhausted(
        app_session,
        reason,
        run_id: run_id,
        issue_id: Map.get(issue, :id),
        issue_identifier: Map.get(issue, :identifier)
      )
    end

    turn_terminal_event = TurnEvents.terminal_event_for_error(reason)

    ObsLogger.emit(
      TurnEvents.terminal_level(turn_terminal_event),
      turn_terminal_event,
      EventFields.turn(
        app_session,
        issue,
        worker_host,
        workspace,
        run_id,
        turn_number,
        max_turns,
        %{
          status: TurnEvents.status_for_event(turn_terminal_event),
          operation: "run_turn",
          duration_ms: RunContext.elapsed_ms(turn_started_at_ms)
        }
        |> Map.merge(TurnEvents.error_fields(reason))
      )
    )

    RunContext.workspace_result(error, worker_host)
  end

  defp emit_continuation_started(refreshed_issue, previous_issue, worker_host, workspace, run_id, turn_number, turn_session) do
    ObsLogger.emit(
      :info,
      :agent_continuation_started,
      EventFields.event(refreshed_issue, worker_host, workspace, %{
        run_id: run_id,
        correlation_id: run_id,
        attempt: turn_number + 1,
        previous_state: previous_issue.state,
        current_state: refreshed_issue.state,
        session_id: turn_result_value(turn_session, :session_id),
        thread_id: turn_result_value(turn_session, :thread_id),
        turn_id: turn_result_value(turn_session, :turn_id)
      })
    )
  end

  defp emit_max_turns_reached(refreshed_issue, worker_host, workspace, run_id, turn_number, turn_session) do
    ObsLogger.emit(
      :warning,
      :agent_max_turns_reached,
      EventFields.event(refreshed_issue, worker_host, workspace, %{
        run_id: run_id,
        correlation_id: run_id,
        attempt: turn_number,
        current_state: refreshed_issue.state,
        session_id: turn_result_value(turn_session, :session_id),
        thread_id: turn_result_value(turn_session, :thread_id),
        turn_id: turn_result_value(turn_session, :turn_id)
      })
    )
  end

  defp continue_with_issue?(%Issue{} = issue, issue_state_fetcher, opts) do
    Continuation.continue_with_issue(issue, issue_state_fetcher, opts)
  end

  defp continue_with_issue?(issue, _issue_state_fetcher, _opts), do: {:done, issue}

  defp turn_result_value(result, key) when is_map(result), do: Map.get(result, key)
end
