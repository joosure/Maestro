defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.CheckStatus do
  @moduledoc """
  Normalizes provider check buckets into readiness status values.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values, as: ReadinessValues
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.CheckStatus.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput

  @passed_status ReadinessValues.passed_status()
  @failed_status ReadinessValues.failed_status()
  @pending_status ReadinessValues.pending_status()
  @unknown_status ReadinessValues.unknown_status()
  @unavailable_status ReadinessValues.unavailable_status()

  @spec status(term()) :: String.t()
  def status(checks) when is_map(checks) do
    checks
    |> Map.get(Contract.runs_key())
    |> runs_status(Map.get(checks, Contract.summary_key()))
  end

  def status(_checks), do: @unknown_status

  defp runs_status(runs, _summary) when is_list(runs) do
    cond do
      runs == [] -> @unavailable_status
      Enum.any?(runs, &(check_bucket(&1) in Contract.failed_buckets())) -> @failed_status
      Enum.any?(runs, &(check_bucket(&1) in Contract.pending_buckets())) -> @pending_status
      Enum.all?(runs, &(check_bucket(&1) in Contract.passed_buckets())) -> @passed_status
      true -> @unknown_status
    end
  end

  defp runs_status(_runs, summary) when is_map(summary) do
    cond do
      summary == %{} -> @unavailable_status
      Enum.any?(Contract.failed_buckets(), fn key -> (RawInput.integer_value(summary, key) || 0) > 0 end) -> @failed_status
      Enum.any?(Contract.pending_buckets(), fn key -> (RawInput.integer_value(summary, key) || 0) > 0 end) -> @pending_status
      Enum.any?(Contract.passed_buckets(), fn key -> (RawInput.integer_value(summary, key) || 0) > 0 end) -> @passed_status
      true -> @unknown_status
    end
  end

  defp runs_status(_runs, _summary), do: @unknown_status

  defp check_bucket(check) when is_map(check) do
    (RawInput.string_value(check, Contract.bucket_key()) || RawInput.string_value(check, Contract.state_key()) || @unknown_status)
    |> String.downcase()
  end

  defp check_bucket(_check), do: @unknown_status
end
