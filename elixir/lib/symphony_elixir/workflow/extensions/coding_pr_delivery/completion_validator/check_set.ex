defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.CheckSet do
  @moduledoc """
  Assembles completion-validator check envelopes from predicates and observations.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Checks
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.ObservedEvidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.ResultBuilder

  @spec validation_checks(map(), String.t() | nil, [String.t()]) :: [map()]
  def validation_checks(evidence, route_key, allowed_routes) do
    [
      ResultBuilder.check(
        Contract.change_proposal_exists_check(),
        Checks.change_proposal_exists?(evidence),
        Contract.linked_change_proposal_required(),
        ObservedEvidence.change_proposal(evidence)
      ),
      ResultBuilder.check(
        Contract.change_proposal_linked_to_tracker_check(),
        Checks.change_proposal_linked_to_tracker?(evidence),
        Contract.tracker_link_required(),
        ObservedEvidence.tracker_link(evidence)
      ),
      ResultBuilder.check(
        Contract.commit_or_diff_exists_check(),
        Checks.commit_or_diff_exists?(evidence),
        Contract.commit_or_diff_required(),
        ObservedEvidence.repo_change(evidence)
      ),
      ResultBuilder.check(
        Contract.checks_read_and_recorded_check(),
        Checks.checks_read_and_recorded?(evidence),
        Contract.checks_read_required(),
        ObservedEvidence.checks(evidence)
      ),
      ResultBuilder.check(
        Contract.tracker_workpad_written_check(),
        Checks.tracker_workpad_written?(evidence),
        Contract.tracker_write_required(),
        ObservedEvidence.tracker_write(evidence)
      ),
      ResultBuilder.check(
        Contract.completion_route_allowed_check(),
        Checks.route_allowed?(route_key, allowed_routes),
        Contract.completion_route_required(),
        ObservedEvidence.route(route_key)
      )
    ]
  end

  @spec merge_gate_checks(map(), map()) :: [map()]
  def merge_gate_checks(evidence, capabilities) do
    [
      ResultBuilder.check(
        Contract.change_proposal_exists_check(),
        Checks.change_proposal_exists?(evidence),
        Contract.linked_change_proposal_required(),
        ObservedEvidence.change_proposal(evidence)
      ),
      ResultBuilder.check(
        Contract.change_proposal_approved_check(),
        Checks.change_proposal_approved?(evidence),
        Contract.human_approval_required(),
        ObservedEvidence.approval(evidence)
      ),
      ResultBuilder.check(
        Contract.checks_passing_check(),
        Checks.checks_passing?(evidence),
        Contract.checks_passing_required(),
        ObservedEvidence.checks(evidence)
      ),
      ResultBuilder.check(
        Contract.merge_capability_available_check(),
        Checks.merge_capability_available?(capabilities),
        Contract.merge_capability_required(),
        ObservedEvidence.merge_capability(capabilities)
      ),
      ResultBuilder.check(
        Contract.tracker_merge_state_observed_check(),
        Checks.tracker_merge_state_observed?(evidence),
        Contract.tracker_merge_state_required(),
        ObservedEvidence.tracker_merge_state(evidence)
      )
    ]
  end
end
