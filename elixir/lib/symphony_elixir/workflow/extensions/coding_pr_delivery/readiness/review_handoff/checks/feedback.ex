defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Feedback do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Support
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder

  import ResultBuilder,
    only: [
      check_key: 1,
      failed_check: 4,
      missing_check: 4,
      observed_evidence_code: 1,
      passed_check: 3,
      reason_code: 1
    ]

  @feedback_key Evidence.feedback_key()
  @status_key Evidence.status_key()
  @actionable_count_key Evidence.actionable_count_key()
  @passing_feedback_statuses Contract.passing_feedback_statuses()

  @spec check(map() | term()) :: map()
  def check(feedback) do
    cond do
      not is_map(feedback) or map_size(feedback) == 0 ->
        missing_check(check_key(:feedback_clear), reason_code(:feedback_evidence_missing), "Review feedback evidence is required.", [])

      Map.get(feedback, @status_key) in @passing_feedback_statuses and Support.integer(Map.get(feedback, @actionable_count_key), 0) == 0 ->
        passed_check(check_key(:feedback_clear), observed_evidence_code(:feedback_clear), Support.observed(feedback, @feedback_key))

      true ->
        failed_check(
          check_key(:feedback_clear),
          reason_code(:feedback_action_required),
          "Actionable review feedback must be resolved or explicitly acknowledged before handoff.",
          Support.observed(feedback, @feedback_key)
        )
    end
  end
end
