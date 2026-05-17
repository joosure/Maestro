defmodule SymphonyElixir.Agent.Runner.Execution do
  @moduledoc false

  alias SymphonyElixir.Agent.Runner.{EventFields, RunContext, RunEvents, TurnEvents, WorkerAttempt, WorkerUpdates}
  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.OperationStatus

  @spec run(map(), pid() | nil, keyword()) :: :ok
  def run(issue, update_recipient \\ nil, opts \\ []) do
    worker_host =
      opts
      |> Keyword.get(:worker_host)
      |> RunContext.selected_worker_host(Config.settings!().worker.ssh_hosts)

    run_id = Keyword.get(opts, :run_id) || RunContext.generate_run_id(issue)
    started_at_ms = RunContext.monotonic_ms()

    ObsLogger.emit(
      :info,
      :agent_run_started,
      EventFields.event(issue, worker_host, nil, %{
        run_id: run_id,
        correlation_id: run_id,
        status: OperationStatus.started(),
        attempt: Keyword.get(opts, :attempt)
      })
    )

    result =
      try do
        WorkerAttempt.run(issue, update_recipient, opts, worker_host, run_id)
      rescue
        exception ->
          RunEvents.emit_exception_terminal(
            exception,
            __STACKTRACE__,
            issue,
            worker_host,
            nil,
            run_id,
            started_at_ms,
            Keyword.get(opts, :attempt)
          )

          reraise(exception, __STACKTRACE__)
      catch
        kind, reason ->
          stacktrace = __STACKTRACE__

          RunEvents.emit_catch_terminal(
            kind,
            reason,
            stacktrace,
            issue,
            worker_host,
            nil,
            run_id,
            started_at_ms,
            Keyword.get(opts, :attempt)
          )

          :erlang.raise(kind, reason, stacktrace)
      end

    handle_result(result, issue, update_recipient, opts, worker_host, run_id, started_at_ms)
  end

  defp handle_result(:ok, issue, _update_recipient, opts, worker_host, run_id, started_at_ms) do
    ObsLogger.emit(
      :info,
      :agent_run_completed,
      EventFields.event(issue, worker_host, nil, %{
        run_id: run_id,
        correlation_id: run_id,
        status: OperationStatus.completed(),
        attempt: Keyword.get(opts, :attempt),
        duration_ms: RunContext.elapsed_ms(started_at_ms)
      })
    )

    :ok
  end

  defp handle_result({:error, reason}, issue, update_recipient, opts, worker_host, run_id, started_at_ms) do
    failure_class = TurnEvents.run_failure_class(reason, worker_host)

    WorkerUpdates.runtime_info(
      update_recipient,
      issue,
      worker_host,
      nil,
      run_id,
      %{
        failure_class: failure_class,
        error: inspect(reason)
      }
    )

    ObsLogger.emit(
      :error,
      :agent_run_failed,
      EventFields.event(
        issue,
        worker_host,
        nil,
        Map.merge(
          %{run_id: run_id, correlation_id: run_id},
          Map.merge(
            ObsLogger.error_details(reason),
            %{
              status: OperationStatus.failed(),
              attempt: Keyword.get(opts, :attempt),
              duration_ms: RunContext.elapsed_ms(started_at_ms)
            }
            |> Map.merge(RunContext.failure_class_field(failure_class))
            |> Map.merge(TurnEvents.provider_error_fields(reason))
          )
        )
      )
    )

    raise RuntimeError, "Agent run failed for #{RunContext.issue_context(issue)}: #{inspect(reason)}"
  end
end
