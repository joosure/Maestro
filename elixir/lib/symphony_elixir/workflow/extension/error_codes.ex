defmodule SymphonyElixir.Workflow.Extension.ErrorCodes do
  @moduledoc """
  Stable machine-code contract for workflow extension boundaries.

  These codes describe platform extension registration and extension-owned
  state-store failures. Concrete extension business rules should add their own
  domain context without changing these platform-level codes.
  """

  @invalid_runtime_extension "invalid_workflow_runtime_extension"
  @invalid_runtime_extension_options "invalid_workflow_runtime_extension_options"
  @invalid_runtime_context "invalid_workflow_extension_runtime_context"
  @runtime_extension_failed "workflow_runtime_extension_failed"
  @runtime_command_error "workflow_extension_runtime_command_error"
  @invalid_canonical_identity "invalid_workflow_extension_canonical_identity"
  @invalid_contribution "invalid_workflow_extension_contribution"
  @invalid_operator_command "invalid_workflow_extension_operator_command"
  @invalid_tool_result_recorder "invalid_workflow_extension_tool_result_recorder"
  @tool_result_recorder_error "workflow_extension_tool_result_recorder_error"
  @invalid_state_record "invalid_workflow_extension_state_record"
  @state_store_error "workflow_extension_state_store_error"

  @spec invalid_runtime_extension() :: String.t()
  def invalid_runtime_extension, do: @invalid_runtime_extension

  @spec invalid_runtime_extension_options() :: String.t()
  def invalid_runtime_extension_options, do: @invalid_runtime_extension_options

  @spec invalid_runtime_context() :: String.t()
  def invalid_runtime_context, do: @invalid_runtime_context

  @spec runtime_extension_failed() :: String.t()
  def runtime_extension_failed, do: @runtime_extension_failed

  @spec runtime_command_error() :: String.t()
  def runtime_command_error, do: @runtime_command_error

  @spec invalid_canonical_identity() :: String.t()
  def invalid_canonical_identity, do: @invalid_canonical_identity

  @spec invalid_contribution() :: String.t()
  def invalid_contribution, do: @invalid_contribution

  @spec invalid_operator_command() :: String.t()
  def invalid_operator_command, do: @invalid_operator_command

  @spec invalid_tool_result_recorder() :: String.t()
  def invalid_tool_result_recorder, do: @invalid_tool_result_recorder

  @spec tool_result_recorder_error() :: String.t()
  def tool_result_recorder_error, do: @tool_result_recorder_error

  @spec invalid_state_record() :: String.t()
  def invalid_state_record, do: @invalid_state_record

  @spec state_store_error() :: String.t()
  def state_store_error, do: @state_store_error
end
