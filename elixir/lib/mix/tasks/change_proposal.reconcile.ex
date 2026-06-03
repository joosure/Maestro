defmodule Mix.Tasks.ChangeProposal.Reconcile do
  use Mix.Task

  alias SymphonyElixir.CLI.ChangeProposalReconcile, as: ChangeProposalReconcileCLI
  alias SymphonyElixir.Observability.EventStore

  @shortdoc "Run targeted change-proposal reconciliation for one issue"

  @moduledoc """
  Runs operator-triggered targeted change-proposal reconciliation for one issue.

  The task never broad-scans tracker source routes. It always supplies the
  explicit `--issue` value to the reconciler as a runtime targeted candidate.

  By default this task is dry-run and does not write tracker state. State-write
  mode requires `--confirm-state-write`; the reconciler still performs the same
  source-route validation and tracker state precondition checks as the poll
  cycle.

  The command loads workflow-local structured KnownTarget records from
  `.symphony/change_proposal_known_targets.json` beside the selected workflow
  file. This lets operator one-shot reconciliation use the same persisted PR/MR
  reference source as the main service, without scraping tracker comments.

  Usage:

      mix change_proposal.reconcile [--workflow <path>|--template <alias>] --issue <id> [--json]
      mix change_proposal.reconcile [--workflow <path>|--template <alias>] --issue <id> --confirm-state-write [--json]
  """

  @impl Mix.Task
  def run(args) do
    if Enum.any?(args, &(&1 in ["--help", "-h"])) do
      Mix.shell().info(@moduledoc)
    else
      with :ok <- ensure_runtime_started() do
        {stdout, stderr, exit_code} = ChangeProposalReconcileCLI.evaluate(args)

        if stdout != "", do: IO.write(stdout)

        case exit_code do
          0 ->
            :ok

          _other ->
            message =
              stderr
              |> String.trim()
              |> case do
                "" -> "change_proposal.reconcile failed"
                value -> value
              end

            Mix.raise(message)
        end
      end
    end
  end

  defp ensure_runtime_started do
    with {:ok, _logger_apps} <- Application.ensure_all_started(:logger),
         {:ok, _req_apps} <- Application.ensure_all_started(:req),
         {:ok, _yaml_apps} <- Application.ensure_all_started(:yaml_elixir),
         :ok <- ensure_event_store_started() do
      :ok
    else
      {:error, reason} -> Mix.raise("Failed to start change proposal reconcile runtime dependencies: #{inspect(reason)}")
    end
  end

  defp ensure_event_store_started do
    case Process.whereis(EventStore) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case EventStore.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
