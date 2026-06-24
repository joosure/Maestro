defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks do
  @moduledoc """
  Review-handoff check orchestration for Coding PR Delivery.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.ChangeProposal
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.ChangeProposalChecks
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Feedback
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Repository
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Validation
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Workpad
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceSource
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff

  @workpad_key Evidence.workpad_key()
  @repo_key Evidence.repo_key()
  @change_proposal_key Evidence.change_proposal_key()
  @validation_key Evidence.validation_key()
  @checks_key Evidence.checks_key()
  @feedback_key Evidence.feedback_key()

  @spec checks(map() | struct() | nil, map(), map(), keyword()) :: [map()]
  def checks(workflow, issue, observations, opts) do
    repo = EvidenceSource.observation(observations, @repo_key)
    change_proposal = EvidenceSource.observation(observations, @change_proposal_key)
    validation = EvidenceSource.observation(observations, @validation_key)
    change_proposal_checks = EvidenceSource.observation(observations, @checks_key)
    feedback = EvidenceSource.observation(observations, @feedback_key)
    readiness_observations = [repo, change_proposal, validation, change_proposal_checks, feedback]

    [
      Workpad.check(EvidenceSource.observation(observations, @workpad_key), readiness_observations),
      Repository.check(repo),
      Validation.check(validation, repo, change_proposal),
      ChangeProposal.check(workflow, change_proposal),
      ChangeProposalChecks.check(workflow, change_proposal_checks, repo, change_proposal),
      Feedback.check(feedback)
    ] ++ StructuredPlanReviewHandoff.checks(workflow, issue, observations, opts)
  end
end
