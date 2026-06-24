defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.ErrorCodes do
  @moduledoc """
  Machine-code contract for workflow structured-plan Workpad rendering.

  Generic validation codes are delegated to the Agent execution-plan validation
  contract. This module owns only rendering-specific codes.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes

  @rendering_failed "rendering_failed"
  @render_marker_mismatch "render_marker_mismatch"
  @invalid_arguments_reason :invalid_arguments

  @spec rendering_failed() :: String.t()
  def rendering_failed, do: @rendering_failed

  @spec render_marker_mismatch() :: String.t()
  def render_marker_mismatch, do: @render_marker_mismatch

  @spec invalid_arguments_reason(String.t()) :: {:invalid_arguments, String.t()}
  def invalid_arguments_reason(message) when is_binary(message), do: {@invalid_arguments_reason, message}

  @spec unknown_key() :: String.t()
  defdelegate unknown_key, to: ValidationErrorCodes

  @spec missing_required_field() :: String.t()
  defdelegate missing_required_field, to: ValidationErrorCodes

  @spec invalid_schema() :: String.t()
  defdelegate invalid_schema, to: ValidationErrorCodes

  @spec invalid_enum() :: String.t()
  defdelegate invalid_enum, to: ValidationErrorCodes

  @spec invalid_type() :: String.t()
  defdelegate invalid_type, to: ValidationErrorCodes

  @spec invalid_extension_key() :: String.t()
  defdelegate invalid_extension_key, to: ValidationErrorCodes
end
