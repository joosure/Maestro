defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.ChangeProposalChecks do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Support
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Target
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

  @checks_key Evidence.checks_key()
  @status_key Evidence.status_key()
  @head_sha_key Evidence.head_sha_key()
  @unknown_status Values.unknown_status()
  @unavailable_status Values.unavailable_status()
  @not_required_status Values.not_required_status()
  @passing_check_statuses Contract.passing_check_statuses()

  @spec check(map() | struct() | nil, map() | term(), map() | term(), map() | term()) :: map()
  def check(workflow, checks, repo, change_proposal) do
    cond do
      not Target.change_proposal_required?(workflow) ->
        passed_check(check_key(:change_proposal_checks), observed_evidence_code(:checks_ready), [])

      not is_map(checks) or map_size(checks) == 0 ->
        missing_check(check_key(:change_proposal_checks), reason_code(:change_proposal_checks_evidence_missing), "Change-proposal check evidence is required.", [])

      Map.get(checks, @status_key) == @not_required_status and not Target.change_proposal_checks_not_required?(workflow) ->
        missing_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_absent_without_config),
          "Change-proposal checks may be not_required only when trusted workflow policy explicitly declares checks are not required.",
          Support.observed(checks, @checks_key)
        )

      Map.get(checks, @status_key) == @not_required_status and Support.stale_observation?(checks, repo, change_proposal) ->
        stale_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_observation_stale),
          "Change-proposal checks must be observed after the latest implementation or change-proposal evidence.",
          Support.observed(checks, @checks_key)
        )

      Map.get(checks, @status_key) == @not_required_status ->
        passed_check(check_key(:change_proposal_checks), observed_evidence_code(:checks_ready), Support.observed(checks, @checks_key))

      Map.get(checks, @status_key) == @unavailable_status ->
        missing_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_unavailable),
          "Change-proposal checks are unavailable and must be normalized to not_required by policy before handoff.",
          Support.observed(checks, @checks_key)
        )

      Map.get(checks, @status_key) in @passing_check_statuses and Support.stale_head?(Map.get(checks, @head_sha_key), Support.current_head(repo, change_proposal)) ->
        stale_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_head_stale),
          "Change-proposal checks must be observed for the latest published head.",
          Support.observed(checks, @checks_key)
        )

      Map.get(checks, @status_key) in @passing_check_statuses and Support.stale_observation?(checks, repo, change_proposal) ->
        stale_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_observation_stale),
          "Change-proposal checks must be observed after the latest implementation or change-proposal evidence.",
          Support.observed(checks, @checks_key)
        )

      Map.get(checks, @status_key) in @passing_check_statuses ->
        passed_check(check_key(:change_proposal_checks), observed_evidence_code(:checks_ready), Support.observed(checks, @checks_key))

      Map.get(checks, @status_key) == @unknown_status ->
        failed_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_unknown),
          "Change-proposal checks must be known, passing, or explicitly not required.",
          Support.observed(checks, @checks_key)
        )

      true ->
        failed_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_not_passing),
          "Change-proposal checks must pass or be explicitly not required.",
          Support.observed(checks, @checks_key)
        )
    end
  end
end
