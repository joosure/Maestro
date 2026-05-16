defmodule SymphonyElixir.ChangeProposalReconciliation.Counters do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Facts

  @spec update_failed_check_counter(map(), Issue.t(), Facts.t()) :: {map(), non_neg_integer()}
  def update_failed_check_counter(state, _issue, %Facts{check_summary: check_summary})
      when is_map(state) and check_summary != :failing do
    {state, 0}
  end

  def update_failed_check_counter(state, %Issue{} = issue, %Facts{} = facts) when is_map(state) do
    key = failed_check_counter_key(issue, facts)
    failed_counts = failed_check_counts(state)
    count = Map.get(failed_counts, key, 0) + 1

    updated_reconciliation =
      state
      |> reconciliation_state()
      |> Map.put(:failed_check_counts, Map.put(failed_counts, key, count))

    {Map.put(state, :change_proposal_reconciliation, updated_reconciliation), count}
  end

  defp failed_check_counts(%{change_proposal_reconciliation: reconciliation})
       when is_map(reconciliation) do
    case Map.get(reconciliation, :failed_check_counts) do
      counts when is_map(counts) -> counts
      _counts -> %{}
    end
  end

  defp failed_check_counts(_state), do: %{}

  defp failed_check_counter_key(%Issue{} = issue, %Facts{} = facts) do
    {issue.id, facts.number || facts.url || facts.branch, facts.head_sha}
  end

  defp reconciliation_state(%{change_proposal_reconciliation: reconciliation})
       when is_map(reconciliation) do
    reconciliation
  end

  defp reconciliation_state(_state), do: %{}
end
