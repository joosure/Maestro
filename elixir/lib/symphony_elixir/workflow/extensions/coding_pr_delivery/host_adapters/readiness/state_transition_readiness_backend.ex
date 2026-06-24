defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Readiness.StateTransitionReadinessBackend do
  @moduledoc """
  Bundled readiness evidence-store backend backed by the platform store.
  """

  @behaviour SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceStore

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store

  @impl true
  def snapshot(keys, opts), do: Store.snapshot(keys, opts)

  @impl true
  def record(keys, evidence, opts), do: Store.record(keys, evidence, opts)

  @impl true
  def scope_issue_keys(run_id, issue_keys, _opts), do: Store.scope_issue_keys(run_id, issue_keys)
end
