defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates do
  @moduledoc """
  Gate keys and defaults for workflow structured execution plan adoption.

  Gate keys are external configuration identifiers. They live at this boundary
  so runtime modules can use stable accessors instead of repeating literals.
  """

  @enabled_gate_key "workflow.structured_execution_plan.enabled"
  @render_workpad_gate_key "workflow.structured_execution_plan.render_workpad"
  @transition_readiness_required_gate_key "workflow.structured_execution_plan.transition_readiness_required"
  @provider_adapters_enabled_gate_key "workflow.structured_execution_plan.provider_adapters.enabled"
  @gate_keys [
    @enabled_gate_key,
    @render_workpad_gate_key,
    @transition_readiness_required_gate_key,
    @provider_adapters_enabled_gate_key
  ]
  @gate_defaults Map.new(@gate_keys, &{&1, false})

  @spec gate_defaults() :: %{String.t() => boolean()}
  def gate_defaults, do: @gate_defaults

  @spec gate_keys() :: [String.t()]
  def gate_keys, do: @gate_keys

  @spec enabled_gate_key() :: String.t()
  def enabled_gate_key, do: @enabled_gate_key

  @spec render_workpad_gate_key() :: String.t()
  def render_workpad_gate_key, do: @render_workpad_gate_key

  @spec transition_readiness_required_gate_key() :: String.t()
  def transition_readiness_required_gate_key, do: @transition_readiness_required_gate_key

  @spec provider_adapters_enabled_gate_key() :: String.t()
  def provider_adapters_enabled_gate_key, do: @provider_adapters_enabled_gate_key
end
