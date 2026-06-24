defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.TransitionDefaults do
  @moduledoc false

  alias SymphonyElixir.Tracker

  @spec fetch_issue_states_by_ids([String.t()], keyword()) :: {:ok, list()} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, opts), do: Tracker.fetch_issue_states_by_ids(issue_ids, opts)

  @spec update_issue_state(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, target_state, opts), do: Tracker.update_issue_state(issue_id, target_state, opts)
end
