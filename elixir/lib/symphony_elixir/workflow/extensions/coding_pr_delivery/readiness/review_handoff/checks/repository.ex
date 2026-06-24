defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Repository do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Support
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder

  import ResultBuilder,
    only: [
      check_key: 1,
      missing_check: 4,
      observed_evidence_code: 1,
      passed_check: 3,
      reason_code: 1
    ]

  @repo_key Evidence.repo_key()
  @change_kind_key Evidence.change_kind_key()
  @no_code_change_justification_key Evidence.no_code_change_justification_key()
  @code_change_kind Evidence.code_change_kind()
  @no_code_change_kind Evidence.no_code_change_kind()

  @spec check(map() | term()) :: map()
  def check(repo) do
    cond do
      not is_map(repo) or map_size(repo) == 0 ->
        missing_check(check_key(:implementation_evidence), reason_code(:repo_implementation_evidence_missing), "Repository implementation evidence is required.", [])

      Map.get(repo, @change_kind_key) == @code_change_kind and Support.code_change_observed?(repo) ->
        passed_check(check_key(:implementation_evidence), observed_evidence_code(:repo_code_change), Support.observed(repo, @repo_key))

      Map.get(repo, @change_kind_key) == @no_code_change_kind and Support.present?(Map.get(repo, @no_code_change_justification_key)) ->
        passed_check(check_key(:implementation_evidence), observed_evidence_code(:repo_no_code_change_justification), Support.observed(repo, @repo_key))

      Map.get(repo, @change_kind_key) == @no_code_change_kind ->
        missing_check(
          check_key(:implementation_evidence),
          reason_code(:repo_no_code_change_justification_missing),
          "No-code-change handoff requires a structured justification.",
          Support.observed(repo, @repo_key)
        )

      true ->
        missing_check(
          check_key(:implementation_evidence),
          reason_code(:repo_implementation_evidence_missing),
          "Repository evidence must include code-change details or a no-code-change justification.",
          Support.observed(repo, @repo_key)
        )
    end
  end
end
