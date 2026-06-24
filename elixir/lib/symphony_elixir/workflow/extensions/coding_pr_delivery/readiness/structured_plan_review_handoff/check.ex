defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Check do
  @moduledoc """
  Readiness check envelope builder for structured-plan review handoff.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.{Result, Values}

  @status_key Evidence.status_key()
  @reason_code_key Result.reason_code_key()
  @passed_status Values.passed_status()
  @missing_status Values.missing_status()
  @failed_status Values.failed_status()
  @stale_status Values.stale_status()

  @spec passed(String.t(), [String.t()]) :: map()
  def passed(key, observed), do: build(key, @passed_status, nil, observed, observed)

  @spec missing(String.t(), String.t(), String.t(), [String.t()]) :: map()
  def missing(key, reason_code, detail, observed), do: build(key, @missing_status, reason_code, detail, observed)

  @spec failed(String.t(), String.t(), String.t(), [String.t()]) :: map()
  def failed(key, reason_code, detail, observed), do: build(key, @failed_status, reason_code, detail, observed)

  @spec stale(String.t(), String.t(), String.t(), [String.t()]) :: map()
  def stale(key, reason_code, detail, observed), do: build(key, @stale_status, reason_code, detail, observed)

  defp build(key, status, reason_code, required_evidence, observed_evidence) do
    %{
      ReadinessContract.key_key() => key,
      @status_key => status,
      @reason_code_key => reason_code,
      ReadinessContract.required_evidence_key() => required_evidence,
      ReadinessContract.observed_evidence_key() => observed_evidence
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
