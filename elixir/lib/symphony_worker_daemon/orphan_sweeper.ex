defmodule SymphonyWorkerDaemon.OrphanSweeper do
  @moduledoc false

  alias SymphonyElixir.Platform.Process, as: PlatformProcess
  alias SymphonyWorkerDaemon.OrphanSweeper.{LedgerRecorder, ProcessControl, Result, SessionCandidate}
  alias SymphonyWorkerDaemon.Session.Ledger

  @default_grace_ms 500
  @default_kill_wait_ms 500
  @default_poll_ms 25

  @type sweep_result :: %{
          candidates: non_neg_integer(),
          terminated: non_neg_integer(),
          already_exited: non_neg_integer(),
          skipped: non_neg_integer(),
          failed: non_neg_integer()
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {Task, :start_link, [fn -> sweep(opts) end]},
      restart: :temporary,
      type: :worker
    }
  end

  @spec sweep(keyword()) :: sweep_result()
  def sweep(opts) when is_list(opts) do
    if Keyword.get(opts, :enabled?, true) do
      do_sweep(opts)
    else
      Result.empty()
    end
  end

  defp do_sweep(opts) do
    ledger = Keyword.get(opts, :session_ledger)
    workspace_roots = Keyword.get(opts, :workspace_roots, [])
    process_module = Keyword.get(opts, :process_module, PlatformProcess)

    case Ledger.list_sessions(ledger, status: "lost") do
      {:ok, sessions} ->
        sessions
        |> Enum.filter(&SessionCandidate.restart_orphan?/1)
        |> Enum.reduce(Result.empty(), fn session, result ->
          session
          |> sweep_session(ledger, workspace_roots, process_module, opts)
          |> Result.accumulate(result)
        end)

      {:error, _reason} ->
        Result.empty()
    end
  end

  defp sweep_session(session, ledger, workspace_roots, process_module, opts) do
    with {:ok, os_pid} <- SessionCandidate.os_pid(session),
         :ok <- SessionCandidate.validate_workspace(session, workspace_roots) do
      terminate_session_process(session, ledger, os_pid, process_module, opts)
    else
      {:skip, reason} ->
        LedgerRecorder.record(ledger, session, %{
          "orphan_sweep_status" => "skipped",
          "orphan_sweep_reason" => reason
        })

        :skipped
    end
  end

  defp terminate_session_process(session, ledger, os_pid, process_module, opts) do
    if ProcessControl.alive?(process_module, os_pid) do
      termination =
        ProcessControl.terminate(process_module, os_pid,
          process_group?: Keyword.get(opts, :process_group?, true),
          grace_ms: Keyword.get(opts, :grace_ms, @default_grace_ms),
          kill_wait_ms: Keyword.get(opts, :kill_wait_ms, @default_kill_wait_ms),
          poll_ms: Keyword.get(opts, :poll_ms, @default_poll_ms)
        )

      alive? = Map.get(termination, :alive?)
      status = if alive?, do: "termination_failed", else: "terminated"

      LedgerRecorder.record(ledger, session, %{
        "orphan_sweep_status" => status,
        "orphan_sweep_os_pid" => os_pid,
        "orphan_sweep_signals_sent" => Map.get(termination, :signals_sent, []),
        "orphan_sweep_alive_after" => alive?
      })

      if alive?, do: :failed, else: :terminated
    else
      LedgerRecorder.record(ledger, session, %{
        "orphan_sweep_status" => "already_exited",
        "orphan_sweep_os_pid" => os_pid,
        "orphan_sweep_alive_after" => false
      })

      :already_exited
    end
  end
end
