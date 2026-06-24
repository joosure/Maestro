defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Commands do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Events

  @spec release_blocked_issue_if_changed(KnownTarget.t(), boolean(), map()) :: :ok
  def release_blocked_issue_if_changed(%KnownTarget{issue_id: issue_id}, true, context) when is_map(context) do
    command = RuntimeCommand.release_blocked_issue(issue_id, :change_proposal_facts_changed)

    case context.command_handler.(command) do
      :ok -> :ok
      {:ok, _result} -> :ok
      {:error, reason} -> Events.command_failure(issue_id, reason, context)
      other -> Events.command_failure(issue_id, {:invalid_runtime_command_result, other}, context)
    end
  end

  def release_blocked_issue_if_changed(_target, _changed?, _context), do: :ok
end
