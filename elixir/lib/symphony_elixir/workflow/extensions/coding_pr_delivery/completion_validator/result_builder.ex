defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.ResultBuilder do
  @moduledoc """
  Builds stable completion-validation result envelopes.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.RouteRef

  @type validation_result :: %{required(String.t()) => term()}

  @spec check(String.t(), boolean(), String.t(), [String.t()]) :: map()
  def check(key, true, required_evidence, observed_evidence) do
    %{
      ReadinessContract.key_key() => key,
      ReadinessContract.status_key() => ReadinessContract.passed(),
      ReadinessContract.required_evidence_key() => required_evidence,
      ReadinessContract.observed_evidence_key() => observed_evidence
    }
  end

  def check(key, _passed?, required_evidence, observed_evidence) do
    %{
      ReadinessContract.key_key() => key,
      ReadinessContract.status_key() => ReadinessContract.failed(),
      ReadinessContract.required_evidence_key() => required_evidence,
      ReadinessContract.observed_evidence_key() => observed_evidence
    }
  end

  @spec validation_result(map(), String.t() | nil, [String.t()], [map()]) :: validation_result()
  def validation_result(profile_context, route, allowed_routes, checks) do
    %{
      ReadinessContract.status_key() => result_status(checks),
      ReadinessContract.allowed_completion_routes_key() => allowed_routes,
      ReadinessContract.checks_key() => checks,
      ReadinessContract.missing_evidence_key() => missing_evidence(checks),
      ReadinessContract.observed_evidence_key() => observed_evidence(checks)
    }
    |> Map.merge(route_ref_fields(profile_context, route))
  end

  @spec merge_gate_result([map()]) :: validation_result()
  def merge_gate_result(checks) do
    %{
      ReadinessContract.status_key() => result_status(checks),
      ReadinessContract.checks_key() => checks,
      ReadinessContract.missing_evidence_key() => missing_evidence(checks),
      ReadinessContract.observed_evidence_key() => observed_evidence(checks)
    }
  end

  @spec skipped(map(), String.t() | nil, [String.t()]) :: validation_result()
  def skipped(profile_context, route_key, allowed_routes) do
    %{
      ReadinessContract.status_key() => ReadinessContract.skipped(),
      ReadinessContract.allowed_completion_routes_key() => allowed_routes,
      ReadinessContract.checks_key() => [],
      ReadinessContract.missing_evidence_key() => [],
      ReadinessContract.observed_evidence_key() => []
    }
    |> Map.merge(route_ref_fields(profile_context, route_key))
  end

  @spec invalid_options(map()) :: validation_result()
  def invalid_options(_reason) do
    invalid_result(
      Contract.completion_validator_options_valid_check(),
      Contract.valid_completion_validator_options_required(),
      Evidence.completion_validator_options_invalid_label()
    )
  end

  @spec invalid_input(map()) :: validation_result()
  def invalid_input(_reason) do
    invalid_result(
      Contract.completion_validator_input_valid_check(),
      Contract.valid_completion_validator_input_required(),
      Evidence.completion_validator_input_invalid_label()
    )
  end

  defp invalid_result(check_key, required_evidence, observed_label) do
    checks = [check(check_key, false, required_evidence, [observed_label])]

    %{
      ReadinessContract.status_key() => ReadinessContract.failed(),
      ReadinessContract.checks_key() => checks,
      ReadinessContract.missing_evidence_key() => missing_evidence(checks),
      ReadinessContract.observed_evidence_key() => observed_evidence(checks)
    }
  end

  defp result_status(checks) do
    if Enum.all?(checks, &ReadinessContract.passed?/1) do
      ReadinessContract.passed()
    else
      ReadinessContract.failed()
    end
  end

  defp missing_evidence(checks) do
    checks
    |> Enum.reject(&ReadinessContract.passed?/1)
    |> Enum.map(&Map.fetch!(&1, ReadinessContract.required_evidence_key()))
  end

  defp observed_evidence(checks) do
    checks
    |> Enum.flat_map(&List.wrap(Map.get(&1, ReadinessContract.observed_evidence_key())))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp route_ref_fields(profile_context, route_key) do
    case RouteRef.new(profile_context, route_key) do
      {:ok, route_ref} -> RouteRef.string_fields(route_ref)
      {:error, _reason} -> RouteRef.string_fields(profile_context, route_key)
    end
  end
end
