defmodule SymphonyElixir.Agent.Runner.WorkerAttempt do
  @moduledoc false

  alias SymphonyElixir.Agent.Runner.{EventFields, RunContext, SessionLoop, WorkerUpdates}
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Workspace

  @type worker_host :: String.t() | nil

  @spec run(map(), pid() | nil, keyword(), worker_host(), String.t()) :: :ok | {:error, term()}
  def run(issue, update_recipient, opts, worker_host, run_id) do
    issue_context = RunContext.run_issue_context(issue, run_id)

    ObsLogger.emit(
      :info,
      :agent_worker_attempt_started,
      EventFields.event(issue, worker_host, nil, %{run_id: run_id, correlation_id: run_id})
    )

    case Workspace.create_for_issue(issue_context, worker_host) do
      {:ok, workspace} ->
        run_in_workspace(workspace, issue, issue_context, update_recipient, opts, worker_host, run_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_in_workspace(workspace, issue, issue_context, update_recipient, opts, worker_host, run_id) do
    WorkerUpdates.runtime_info(update_recipient, issue, worker_host, workspace, run_id)

    try do
      with :ok <- Workspace.run_before_run_hook(workspace, issue_context, worker_host) do
        SessionLoop.run(workspace, issue, update_recipient, opts, worker_host, run_id)
      end
    after
      Workspace.run_after_run_hook(workspace, issue_context, worker_host)
    end
  end
end
