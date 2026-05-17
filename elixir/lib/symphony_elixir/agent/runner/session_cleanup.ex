defmodule SymphonyElixir.Agent.Runner.SessionCleanup do
  @moduledoc false

  alias SymphonyElixir.Agent.Runner.EventFields
  alias SymphonyElixir.Agent.Runner.ProviderOptions
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.OperationStatus

  @type worker_host :: String.t() | nil

  @spec stop(term(), keyword(), term(), worker_host(), Path.t() | nil, String.t(), String.t()) ::
          :ok | {:error, term()}
  def stop(session, stop_opts, issue, worker_host, workspace, run_id, reason)
      when is_list(stop_opts) and is_binary(reason) do
    cleanup_started_at_ms = monotonic_ms()

    cleanup_fields =
      EventFields.event(issue, worker_host, workspace, %{
        run_id: run_id,
        correlation_id: run_id,
        status: OperationStatus.started(),
        operation: "stop_session",
        session_id: EventFields.session_value(session, :session_id),
        thread_id: EventFields.session_value(session, :thread_id),
        cleanup_resources: ["session"],
        resource_type: "session",
        cleanup_reason: reason
      })

    ObsLogger.emit(:info, :agent_cleanup_started, cleanup_fields)

    stop_opts =
      stop_opts
      |> Keyword.put_new(:issue, issue)
      |> Keyword.put_new(:issue_id, Map.get(issue, :id))
      |> Keyword.put_new(:issue_identifier, Map.get(issue, :identifier))
      |> Keyword.put_new(:run_id, run_id)

    case AgentProvider.stop_session(session, stop_opts) do
      :ok ->
        ObsLogger.emit(
          :info,
          :agent_cleanup_completed,
          Map.merge(cleanup_fields, %{
            status: OperationStatus.completed(),
            duration_ms: elapsed_ms(cleanup_started_at_ms)
          })
        )

        :ok

      {:error, cleanup_error} = error ->
        ObsLogger.emit(
          :error,
          :agent_cleanup_failed,
          cleanup_fields
          |> Map.merge(%{
            status: OperationStatus.failed(),
            duration_ms: elapsed_ms(cleanup_started_at_ms)
          })
          |> Map.merge(ObsLogger.error_details(cleanup_error))
        )

        error
    end
  end

  @spec stop_options(term(), term(), term()) :: keyword()
  def stop_options(session, result, issue) do
    result
    |> AgentProvider.session_stop_options(issue, ProviderOptions.from_session(session))
    |> Keyword.put_new(:issue, issue)
    |> Keyword.put_new(:issue_id, Map.get(issue, :id))
    |> Keyword.put_new(:issue_identifier, Map.get(issue, :identifier))
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
  defp elapsed_ms(started_at_ms), do: max(monotonic_ms() - started_at_ms, 0)
end
