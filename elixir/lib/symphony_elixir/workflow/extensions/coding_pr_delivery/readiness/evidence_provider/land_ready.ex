defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.LandReady do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts

  @spec ready?(Facts.t()) :: boolean()
  def ready?(%Facts{} = facts) do
    facts.provider_state == Contract.provider_state_open() and
      facts.review_summary == Contract.review_summary_approved() and
      facts.check_summary == Contract.check_summary_passing() and
      facts.mergeability_summary == Contract.mergeability_summary_mergeable() and
      facts.unresolved_actionable_feedback? == false
  end

  def ready?(_facts), do: false
end
