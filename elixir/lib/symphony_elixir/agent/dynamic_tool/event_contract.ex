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

  @dynamic_tool_bridge_component "agent.dynamic_tool_bridge"
  @dynamic_tool_failure_policy_component "agent.dynamic_tool_failure_policy"

  @status_succeeded "succeeded"
  @status_failed "failed"
  @status_rejected "rejected"

  @events [
    {@tool_call_requested_event, nil},
    {@tool_call_started_event, nil},
    {@tool_call_succeeded_event, @status_succeeded},
    {@tool_call_failed_event, @status_failed},
    {@tool_call_rejected_event, @status_rejected},
    {@typed_tool_failure_policy_blocked_event, nil},
    {@typed_tool_failure_policy_skipped_unscoped_event, nil}
  ]

  @event_name_by_atom Map.new(@events, fn {event, _status} -> {event, Atom.to_string(event)} end)
  @event_atom_by_name Map.new(@event_name_by_atom, fn {event, name} -> {name, event} end)
  @terminal_status_by_event_name Map.new(for {event, status} <- @events, is_binary(status), do: {Atom.to_string(event), status})
  @terminal_event_names for {event, status} <- @events, is_binary(status), do: Atom.to_string(event)

  @unsupported_tool "unsupported_tool"
  @untyped_tool "untyped_dynamic_tool"
  @alias_tool "dynamic_tool_alias"
  @invalid_tool_metadata "invalid_dynamic_tool_metadata"
  @unknown_tool "unknown"

  @type event_atom ::
          :tool_call_requested
          | :tool_call_started
          | :tool_call_succeeded
          | :tool_call_failed
          | :tool_call_rejected
          | :typed_tool_failure_policy_blocked
          | :typed_tool_failure_policy_skipped_unscoped
  @type event_name :: String.t()
  @type terminal_status :: String.t()
  @type error_code :: String.t()

  @spec tool_call_requested_event() :: event_atom()
  def tool_call_requested_event, do: @tool_call_requested_event

  @spec tool_call_started_event() :: event_atom()
  def tool_call_started_event, do: @tool_call_started_event

  @spec tool_call_succeeded_event() :: event_atom()
  def tool_call_succeeded_event, do: @tool_call_succeeded_event

  @spec tool_call_failed_event() :: event_atom()
  def tool_call_failed_event, do: @tool_call_failed_event

  @spec tool_call_rejected_event() :: event_atom()
  def tool_call_rejected_event, do: @tool_call_rejected_event

  @spec typed_tool_failure_policy_skipped_unscoped_event() :: event_atom()
  def typed_tool_failure_policy_skipped_unscoped_event, do: @typed_tool_failure_policy_skipped_unscoped_event

  @spec typed_tool_failure_policy_blocked_event() :: event_atom()
  def typed_tool_failure_policy_blocked_event, do: @typed_tool_failure_policy_blocked_event

  @spec dynamic_tool_bridge_component() :: String.t()
  def dynamic_tool_bridge_component, do: @dynamic_tool_bridge_component

  @spec dynamic_tool_failure_policy_component() :: String.t()
  def dynamic_tool_failure_policy_component, do: @dynamic_tool_failure_policy_component

  @spec event_name(event_atom() | event_name()) :: event_name() | nil
  def event_name(event) when is_atom(event), do: Map.get(@event_name_by_atom, event)

  def event_name(event) when is_binary(event) do
    if Map.has_key?(@event_atom_by_name, event), do: event
  end

  def event_name(_event), do: nil

  @spec event_atom(event_atom() | event_name()) :: event_atom() | nil
  def event_atom(event) when is_atom(event) do
    if Map.has_key?(@event_name_by_atom, event), do: event
  end

  def event_atom(event) when is_binary(event), do: Map.get(@event_atom_by_name, event)
  def event_atom(_event), do: nil

  @spec tool_call_requested() :: event_name()
  def tool_call_requested, do: event_name(@tool_call_requested_event)

  @spec tool_call_started() :: event_name()
  def tool_call_started, do: event_name(@tool_call_started_event)

  @spec tool_call_succeeded() :: event_name()
  def tool_call_succeeded, do: event_name(@tool_call_succeeded_event)

  @spec tool_call_failed() :: event_name()
  def tool_call_failed, do: event_name(@tool_call_failed_event)

  @spec tool_call_rejected() :: event_name()
  def tool_call_rejected, do: event_name(@tool_call_rejected_event)

  @spec typed_tool_failure_policy_blocked() :: event_name()
  def typed_tool_failure_policy_blocked, do: event_name(@typed_tool_failure_policy_blocked_event)

  @spec typed_tool_failure_policy_skipped_unscoped() :: event_name()
  def typed_tool_failure_policy_skipped_unscoped, do: event_name(@typed_tool_failure_policy_skipped_unscoped_event)

  @spec terminal_event_names() :: [event_name()]
  def terminal_event_names, do: @terminal_event_names

  @spec status_succeeded() :: terminal_status()
  def status_succeeded, do: @status_succeeded

  @spec status_failed() :: terminal_status()
  def status_failed, do: @status_failed

  @spec status_rejected() :: terminal_status()
  def status_rejected, do: @status_rejected

  @spec status_for_event(term()) :: terminal_status()
  def status_for_event(event) when is_atom(event), do: event |> event_name() |> status_for_event()
  def status_for_event(event) when is_binary(event), do: Map.get(@terminal_status_by_event_name, event, @status_failed)
  def status_for_event(_event), do: @status_failed

  @spec unsupported_tool() :: error_code()
  def unsupported_tool, do: @unsupported_tool

  @spec untyped_tool() :: error_code()
  def untyped_tool, do: @untyped_tool

  @spec alias_tool() :: error_code()
  def alias_tool, do: @alias_tool

  @spec invalid_tool_metadata() :: error_code()
  def invalid_tool_metadata, do: @invalid_tool_metadata

  @spec unknown_tool() :: String.t()
  def unknown_tool, do: @unknown_tool
end
