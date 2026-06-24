defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.ErrorCodes do
  @moduledoc """
  Provider adapter machine-code contract.
  """

  @provider_adapters_gate_disabled "provider_adapters_gate_disabled"
  @structured_plan_missing_required_evidence "structured_plan_missing_required_evidence"

  @spec provider_adapters_gate_disabled() :: String.t()
  def provider_adapters_gate_disabled, do: @provider_adapters_gate_disabled

  @spec structured_plan_missing_required_evidence() :: String.t()
  def structured_plan_missing_required_evidence, do: @structured_plan_missing_required_evidence
end
