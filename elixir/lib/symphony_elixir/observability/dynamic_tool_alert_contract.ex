defmodule SymphonyElixir.Observability.DynamicToolAlertContract do
  @moduledoc """
  Stable Dynamic Tool observability alert codes, categories, and messages.
  """

  alias SymphonyElixir.Observability.DynamicToolMetrics

  @raw_tool_attempts_code DynamicToolMetrics.raw_tool_attempts()
  @unsupported_tool_calls_code "unsupported_tool_calls"
  @provider_capability_unavailable_unknown_code "provider_capability_unavailable_unknown"
  @provider_capability_unavailable_known_code "provider_capability_unavailable_known"

  @regression_category "regression"
  @tool_surface_regression_category "tool_surface_regression"
  @provider_capability_category "provider_capability"

  @raw_tool_attempts_message "Normal workflow sessions must not attempt raw or non-planned tools."
  @unsupported_tool_calls_message "Unsupported tool calls indicate an agent/tool-surface regression."
  @provider_capability_unavailable_unknown_message "Provider capability unavailable reports without a known capability require operator review."
  @provider_capability_unavailable_known_message "Known provider capability unavailable reports are informational and should not be treated as workflow failures."

  @spec raw_tool_attempts_code() :: String.t()
  def raw_tool_attempts_code, do: @raw_tool_attempts_code

  @spec unsupported_tool_calls_code() :: String.t()
  def unsupported_tool_calls_code, do: @unsupported_tool_calls_code

  @spec provider_capability_unavailable_unknown_code() :: String.t()
  def provider_capability_unavailable_unknown_code, do: @provider_capability_unavailable_unknown_code

  @spec provider_capability_unavailable_known_code() :: String.t()
  def provider_capability_unavailable_known_code, do: @provider_capability_unavailable_known_code

  @spec regression_category() :: String.t()
  def regression_category, do: @regression_category

  @spec tool_surface_regression_category() :: String.t()
  def tool_surface_regression_category, do: @tool_surface_regression_category

  @spec provider_capability_category() :: String.t()
  def provider_capability_category, do: @provider_capability_category

  @spec raw_tool_attempts_message() :: String.t()
  def raw_tool_attempts_message, do: @raw_tool_attempts_message

  @spec unsupported_tool_calls_message() :: String.t()
  def unsupported_tool_calls_message, do: @unsupported_tool_calls_message

  @spec provider_capability_unavailable_unknown_message() :: String.t()
  def provider_capability_unavailable_unknown_message, do: @provider_capability_unavailable_unknown_message

  @spec provider_capability_unavailable_known_message() :: String.t()
  def provider_capability_unavailable_known_message, do: @provider_capability_unavailable_known_message
end
