defmodule SymphonyElixir.Orchestrator.Running do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Running.{Reconciliation, StallDetection}

  def reconcile_issue_states(issues, state, dispatch_context, opts \\ [])

  @spec reconcile_issue_states(list(), map(), map(), keyword()) :: map()
  def reconcile_issue_states(issues, state, dispatch_context, opts),
    do: Reconciliation.reconcile_issue_states(issues, state, dispatch_context, opts)

  def reconcile_stalled(state, timeout_ms, opts \\ [])

  @spec reconcile_stalled(map(), integer(), keyword()) :: map()
  def reconcile_stalled(state, timeout_ms, opts), do: StallDetection.reconcile_stalled(state, timeout_ms, opts)
end
