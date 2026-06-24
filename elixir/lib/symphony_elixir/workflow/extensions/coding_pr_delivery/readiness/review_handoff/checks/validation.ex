defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Validation do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Support
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  import ResultBuilder,
    only: [
      check_key: 1,
      failed_check: 4,
      missing_check: 4,
      observed_evidence_code: 1,
      passed_check: 3,
      reason_code: 1,
      stale_check: 4
    ]

  @validation_key Evidence.validation_key()
  @status_key Evidence.status_key()
  @head_sha_key Evidence.head_sha_key()
  @passed_status Values.passed_status()

  @spec check(map() | term(), map() | term(), map() | term()) :: map()
  def check(validation, repo, change_proposal) do
    cond do
      not is_map(validation) or map_size(validation) == 0 ->
        missing_check(check_key(:validation_passed), reason_code(:validation_evidence_missing), "Passing validation evidence is required.", [])

      Map.get(validation, @status_key) != @passed_status ->
        failed_check(check_key(:validation_passed), reason_code(:validation_not_passed), "Validation evidence must be passing.", Support.observed(validation, @validation_key))

      Support.stale_head?(Support.latest_command_head(validation) || Map.get(validation, @head_sha_key), Support.current_head(repo, change_proposal)) ->
        stale_check(check_key(:validation_passed), reason_code(:validation_head_stale), "Validation must run on the latest published head.", Support.observed(validation, @validation_key))

      Support.stale_observation?(validation, repo, change_proposal) ->
        stale_check(
          check_key(:validation_passed),
          reason_code(:validation_head_stale),
          "Validation must be observed after the latest implementation or change-proposal evidence.",
          Support.observed(validation, @validation_key)
        )

      true ->
        passed_check(check_key(:validation_passed), observed_evidence_code(:validation_passed), Support.observed(validation, @validation_key))
    end
  end
end
