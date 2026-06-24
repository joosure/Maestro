defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.ChangeProposal do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Support
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Target

  import ResultBuilder,
    only: [
      check_key: 1,
      failed_check: 4,
      missing_check: 4,
      observed_evidence_code: 1,
      passed_check: 3,
      reason_code: 1
    ]

  @change_proposal_key Evidence.change_proposal_key()
  @status_key Evidence.status_key()
  @linked_to_tracker_key Evidence.linked_to_tracker_key()
  @passing_change_proposal_statuses Contract.passing_change_proposal_statuses()

  @spec check(map() | struct() | nil, map() | term()) :: map()
  def check(workflow, change_proposal) do
    cond do
      not Target.change_proposal_required?(workflow) ->
        passed_check(check_key(:change_proposal_linked), observed_evidence_code(:change_proposal_not_required), [])

      not is_map(change_proposal) or map_size(change_proposal) == 0 ->
        missing_check(check_key(:change_proposal_linked), reason_code(:change_proposal_evidence_missing), "A change proposal must be created and observed before review handoff.", [])

      Map.get(change_proposal, @linked_to_tracker_key) != true ->
        missing_check(
          check_key(:change_proposal_linked),
          reason_code(:change_proposal_tracker_link_missing),
          "The change proposal must be linked to the tracker issue through structured tracker attachment evidence.",
          Support.observed(change_proposal, @change_proposal_key)
        )

      Map.get(change_proposal, @status_key) in @passing_change_proposal_statuses ->
        passed_check(check_key(:change_proposal_linked), observed_evidence_code(:change_proposal_linked), Support.observed(change_proposal, @change_proposal_key))

      true ->
        failed_check(
          check_key(:change_proposal_linked),
          reason_code(:change_proposal_not_ready),
          "The observed change proposal is not in a usable state for review.",
          Support.observed(change_proposal, @change_proposal_key)
        )
    end
  end
end
