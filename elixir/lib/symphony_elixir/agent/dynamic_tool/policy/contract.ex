defmodule SymphonyElixir.Agent.DynamicTool.Policy.Contract do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Metadata

  @tool_key Metadata.Contract.tool()
  @required_exposure_key "requiredExposure"
  @allowed_side_effects_key "allowedSideEffects"
  @field_key "field"
  @reason_key "reason"
  @value_key "value"

  @operator_only_denied "operator_only_dynamic_tool_denied"
  @side_effect_denied "dynamic_tool_side_effect_denied"
  @invalid_policy "invalid_dynamic_tool_policy"

  @operator_only_message "Operator-only dynamic tool requires explicit diagnostics exposure."
  @side_effect_denied_message "Dynamic tool side-effect class is not allowed by policy."
  @invalid_policy_message "Dynamic tool policy config is invalid."

  @spec tool_key() :: String.t()
  def tool_key, do: @tool_key

  @spec required_exposure_key() :: String.t()
  def required_exposure_key, do: @required_exposure_key

  @spec allowed_side_effects_key() :: String.t()
  def allowed_side_effects_key, do: @allowed_side_effects_key

  @spec field_key() :: String.t()
  def field_key, do: @field_key

  @spec reason_key() :: String.t()
  def reason_key, do: @reason_key

  @spec value_key() :: String.t()
  def value_key, do: @value_key

  @spec operator_only_denied() :: String.t()
  def operator_only_denied, do: @operator_only_denied

  @spec side_effect_denied() :: String.t()
  def side_effect_denied, do: @side_effect_denied

  @spec invalid_policy() :: String.t()
  def invalid_policy, do: @invalid_policy

  @spec operator_only_message() :: String.t()
  def operator_only_message, do: @operator_only_message

  @spec side_effect_denied_message() :: String.t()
  def side_effect_denied_message, do: @side_effect_denied_message

  @spec invalid_policy_message() :: String.t()
  def invalid_policy_message, do: @invalid_policy_message
end
