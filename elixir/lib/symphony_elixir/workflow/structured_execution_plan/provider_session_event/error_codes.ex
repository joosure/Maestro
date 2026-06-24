defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.ErrorCodes do
  @moduledoc """
  Provider-session event validation error-code contract.
  """

  @invalid_event "provider_session_event_invalid"
  @missing_required_field "missing_required_field"
  @unknown_field "unknown_field"
  @invalid_value "invalid_value"
  @invalid_type "invalid_type"
  @invalid_enum "invalid_enum"

  @spec invalid_event() :: String.t()
  def invalid_event, do: @invalid_event

  @spec missing_required_field() :: String.t()
  def missing_required_field, do: @missing_required_field

  @spec unknown_field() :: String.t()
  def unknown_field, do: @unknown_field

  @spec invalid_value() :: String.t()
  def invalid_value, do: @invalid_value

  @spec invalid_type() :: String.t()
  def invalid_type, do: @invalid_type

  @spec invalid_enum() :: String.t()
  def invalid_enum, do: @invalid_enum
end
