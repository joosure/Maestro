defmodule SymphonyElixir.Agent.DynamicTool.ExecutionGuard.Contract do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @tool_key Metadata.Contract.tool()
  @tool_alias_of_key Metadata.Contract.tool_alias_of()
  @field_key "field"
  @allowed_values_key "allowedValues"
  @value_key "value"
  @reason_missing "missing"
  @reason_invalid "invalid"

  @untyped_tool_message "Dynamic tool execution requires a canonical typed tool capability."
  @alias_tool_message "Provider-facing dynamic tool aliases cannot execute as authoritative typed tools."
  @invalid_side_effect_message "Dynamic tool metadata requires canonical sideEffect before execution."

  @spec tool_key() :: String.t()
  def tool_key, do: @tool_key

  @spec tool_alias_of_key() :: String.t()
  def tool_alias_of_key, do: @tool_alias_of_key

  @spec field_key() :: String.t()
  def field_key, do: @field_key

  @spec reason_key() :: String.t()
  def reason_key, do: Response.reason_key()

  @spec allowed_values_key() :: String.t()
  def allowed_values_key, do: @allowed_values_key

  @spec value_key() :: String.t()
  def value_key, do: @value_key

  @spec reason_missing() :: String.t()
  def reason_missing, do: @reason_missing

  @spec reason_invalid() :: String.t()
  def reason_invalid, do: @reason_invalid

  @spec untyped_tool_message() :: String.t()
  def untyped_tool_message, do: @untyped_tool_message

  @spec alias_tool_message() :: String.t()
  def alias_tool_message, do: @alias_tool_message

  @spec invalid_side_effect_message() :: String.t()
  def invalid_side_effect_message, do: @invalid_side_effect_message
end
