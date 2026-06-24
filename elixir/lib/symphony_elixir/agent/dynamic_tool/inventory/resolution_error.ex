defmodule SymphonyElixir.Agent.DynamicTool.Inventory.ResolutionError do
  @moduledoc false

  @enforce_keys [:reason]
  defstruct reason: nil,
            capability: nil,
            tools: [],
            value: nil

  @type reason :: :missing_typed_tool | :ambiguous_typed_tool | :invalid_required_capability

  @type t :: %__MODULE__{
          reason: reason(),
          capability: String.t() | nil,
          tools: [String.t()],
          value: term()
        }

  @spec missing_typed_tool(String.t()) :: t()
  def missing_typed_tool(capability) when is_binary(capability) do
    %__MODULE__{reason: :missing_typed_tool, capability: capability}
  end

  @spec ambiguous_typed_tool(String.t(), [String.t()]) :: t()
  def ambiguous_typed_tool(capability, tools) when is_binary(capability) and is_list(tools) do
    %__MODULE__{reason: :ambiguous_typed_tool, capability: capability, tools: Enum.filter(tools, &is_binary/1)}
  end

  @spec invalid_required_capability(term()) :: t()
  def invalid_required_capability(value) do
    %__MODULE__{reason: :invalid_required_capability, value: value}
  end
end
