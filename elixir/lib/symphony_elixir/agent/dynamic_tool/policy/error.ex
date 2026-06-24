defmodule SymphonyElixir.Agent.DynamicTool.Policy.Error do
  @moduledoc false

  @enforce_keys [:reason]
  defstruct reason: nil,
            field: nil,
            value: nil

  @type reason :: :invalid_policy_config | :invalid_allowed_side_effects | :invalid_allow_operator_tools | :invalid_exposure

  @type t :: %__MODULE__{
          reason: reason(),
          field: atom() | nil,
          value: term()
        }

  @spec invalid_policy_config(term()) :: t()
  def invalid_policy_config(value), do: %__MODULE__{reason: :invalid_policy_config, value: value}

  @spec invalid_allowed_side_effects(term()) :: t()
  def invalid_allowed_side_effects(value),
    do: %__MODULE__{reason: :invalid_allowed_side_effects, field: :allowed_side_effects, value: value}

  @spec invalid_allow_operator_tools(term()) :: t()
  def invalid_allow_operator_tools(value),
    do: %__MODULE__{reason: :invalid_allow_operator_tools, field: :allow_operator_tools?, value: value}

  @spec invalid_exposure(term()) :: t()
  def invalid_exposure(value), do: %__MODULE__{reason: :invalid_exposure, field: :exposure, value: value}
end
