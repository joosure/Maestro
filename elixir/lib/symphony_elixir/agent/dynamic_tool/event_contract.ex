defmodule SymphonyElixir.Agent.DynamicTool.EventContract do
  @moduledoc """
  Stable Dynamic Tool event names, terminal statuses, and error codes.

  These values are emitted by provider bridges and consumed by observability
  projections, dashboards, and tests. Keep them in one owner so Dynamic Tool
  telemetry can evolve without string drift.
  """

  @tool_call_requested_event :tool_call_requested
  @tool_call_started_event :tool_call_started
  @tool_call_succeeded_event :tool_call_succeeded
  @tool_call_failed_event :tool_call_failed
  @tool_call_rejected_event :tool_call_rejected
  @typed_tool_failure_policy_blocked_event :typed_tool_failure_policy_blocked
  @typed_tool_failure_policy_skipped_unscoped_event :typed_tool_failure_policy_skipped_unscoped

  @tool_call_succeeded "tool_call_succeeded"
  @tool_call_failed "tool_call_failed"
  @tool_call_rejected "tool_call_rejected"
  @terminal_event_names [@tool_call_succeeded, @tool_call_failed, @tool_call_rejected]

  @status_succeeded "succeeded"
  @status_failed "failed"
  @status_rejected "rejected"

  @unsupported_tool "unsupported_tool"
  @supported_tools_key "supportedTools"
  @unknown_tool "unknown"

  @spec tool_call_requested_event() :: atom()
  def tool_call_requested_event, do: @tool_call_requested_event

  @spec tool_call_started_event() :: atom()
  def tool_call_started_event, do: @tool_call_started_event

  @spec tool_call_succeeded_event() :: atom()
  def tool_call_succeeded_event, do: @tool_call_succeeded_event

  @spec tool_call_failed_event() :: atom()
  def tool_call_failed_event, do: @tool_call_failed_event

  @spec tool_call_rejected_event() :: atom()
  def tool_call_rejected_event, do: @tool_call_rejected_event

  @spec typed_tool_failure_policy_skipped_unscoped_event() :: atom()
  def typed_tool_failure_policy_skipped_unscoped_event, do: @typed_tool_failure_policy_skipped_unscoped_event

  @spec typed_tool_failure_policy_blocked_event() :: atom()
  def typed_tool_failure_policy_blocked_event, do: @typed_tool_failure_policy_blocked_event

  @spec tool_call_succeeded() :: String.t()
  def tool_call_succeeded, do: @tool_call_succeeded

  @spec tool_call_failed() :: String.t()
  def tool_call_failed, do: @tool_call_failed

  @spec tool_call_rejected() :: String.t()
  def tool_call_rejected, do: @tool_call_rejected

  @spec terminal_event_names() :: [String.t()]
  def terminal_event_names, do: @terminal_event_names

  @spec status_succeeded() :: String.t()
  def status_succeeded, do: @status_succeeded

  @spec status_failed() :: String.t()
  def status_failed, do: @status_failed

  @spec status_rejected() :: String.t()
  def status_rejected, do: @status_rejected

  @spec status_for_event(term()) :: String.t()
  def status_for_event(@tool_call_succeeded), do: @status_succeeded
  def status_for_event(@tool_call_failed), do: @status_failed
  def status_for_event(@tool_call_rejected), do: @status_rejected
  def status_for_event(event) when is_atom(event), do: event |> Atom.to_string() |> status_for_event()
  def status_for_event(_event), do: @status_failed

  @spec unsupported_tool() :: String.t()
  def unsupported_tool, do: @unsupported_tool

  @spec supported_tools_key() :: String.t()
  def supported_tools_key, do: @supported_tools_key

  @spec unknown_tool() :: String.t()
  def unknown_tool, do: @unknown_tool
end
