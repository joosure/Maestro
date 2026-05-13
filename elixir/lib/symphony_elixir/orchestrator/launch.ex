defmodule SymphonyElixir.Orchestrator.Launch do
  @moduledoc false

  alias SymphonyElixir.Agent.Runner, as: AgentRunner
  alias SymphonyElixir.Config
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Retry

  @type emit_issue_dispatch ::
          (Logger.level(), atom(), Issue.t(), map(), map() -> :ok)
  @type schedule_retry ::
          (map(), Issue.t(), integer() | nil, map() -> map())
  @type start_child_result :: {:ok, pid(), reference()} | {:error, term()}
  @type start_child ::
          (Issue.t(), pid(), integer() | nil, String.t() | nil, String.t() -> start_child_result())

  @spec spawn_issue(map(), Issue.t(), integer() | nil, pid(), String.t() | nil, keyword()) :: map()
  def spawn_issue(state, %Issue{} = issue, attempt, recipient, worker_host, opts \\ [])
      when is_map(state) and is_pid(recipient) do
    emit_issue_dispatch = Keyword.fetch!(opts, :emit_issue_dispatch)
    schedule_retry = Keyword.fetch!(opts, :schedule_retry)
    start_child = Keyword.get(opts, :start_child, &default_start_child/5)
    now = Keyword.get(opts, :now, &DateTime.utc_now/0)
    run_id = issue_run_id(issue.id)

    case start_child.(issue, recipient, attempt, worker_host, run_id) do
      {:ok, pid, ref} ->
        emit_issue_dispatch.(
          :info,
          :issue_dispatch_started,
          issue,
          state,
          %{attempt: attempt, run_id: run_id, worker_host: worker_host}
        )

        running =
          Map.put(
            running_entries(state),
            issue.id,
            running_entry(issue, pid, ref, run_id, worker_host, attempt, now.())
          )

        %{
          state
          | running: running,
            claimed: MapSet.put(claimed_entries(state), issue.id),
            retry_attempts: Map.delete(retry_attempts(state), issue.id)
        }

      {:error, reason} ->
        emit_issue_dispatch.(
          :error,
          :issue_dispatch_failed,
          issue,
          state,
          %{attempt: attempt, run_id: run_id, worker_host: worker_host, error: inspect(reason)}
        )

        next_attempt = if is_integer(attempt), do: attempt + 1, else: nil

        schedule_retry.(
          state,
          issue,
          next_attempt,
          %{
            identifier: issue.identifier,
            error: "failed to spawn agent: #{inspect(reason)}",
            run_id: run_id,
            agent_provider_kind: Config.agent_provider_kind(),
            worker_host: worker_host
          }
        )
    end
  end

  defp default_start_child(issue, recipient, attempt, worker_host, run_id) do
    case Task.Supervisor.start_child(SymphonyElixir.TaskSupervisor, fn ->
           AgentRunner.run(issue, recipient,
             attempt: attempt,
             worker_host: worker_host,
             run_id: run_id
           )
         end) do
      {:ok, pid} ->
        {:ok, pid, Process.monitor(pid)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp running_entry(issue, pid, ref, run_id, worker_host, attempt, started_at) do
    %{
      pid: pid,
      ref: ref,
      run_id: run_id,
      identifier: issue.identifier,
      issue: issue,
      worker_host: worker_host,
      workspace_path: nil,
      session_id: nil,
      agent_provider_kind: Config.agent_provider_kind(),
      agent_process_pid: nil,
      last_agent_message: nil,
      last_agent_timestamp: nil,
      last_agent_event: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      agent_last_reported_input_tokens: 0,
      agent_last_reported_output_tokens: 0,
      agent_last_reported_total_tokens: 0,
      turn_count: 0,
      failure_class: nil,
      last_error: nil,
      retry_attempt: Retry.normalize_attempt(attempt),
      started_at: started_at
    }
  end

  defp issue_run_id(issue_id) when is_binary(issue_id) do
    "run-" <> Integer.to_string(System.unique_integer([:positive])) <> "-" <> issue_id
  end

  defp issue_run_id(_issue_id) do
    "run-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp running_entries(%{running: running}) when is_map(running), do: running
  defp running_entries(_state), do: %{}

  defp claimed_entries(%{claimed: claimed}) when is_struct(claimed, MapSet), do: claimed
  defp claimed_entries(_state), do: MapSet.new()

  defp retry_attempts(%{retry_attempts: retry_attempts}) when is_map(retry_attempts), do: retry_attempts
  defp retry_attempts(_state), do: %{}
end
