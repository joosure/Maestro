defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values do
  @moduledoc """
  Stable enum-like values used by state-transition readiness payloads.
  """

  @passed_status "passed"
  @blocked_status "blocked"
  @missing_status "missing"
  @failed_status "failed"
  @stale_status "stale"
  @complete_status "complete"
  @incomplete_status "incomplete"
  @unknown_status "unknown"
  @unavailable_status "unavailable"
  @not_required_status "not_required"
  @pending_status "pending"
  @linked_status "linked"
  @created_status "created"
  @updated_status "updated"
  @clear_status "clear"
  @action_required_status "action_required"

  @code_change_kind "code_change"
  @no_code_change_kind "no_code_change"

  @typed_tool_observed_source "typed_tool_observed"
  @tracker_observed_source "tracker_observed"
  @repo_observed_source "repo_observed"
  @repo_provider_observed_source "repo_provider_observed"

  @spec passed_status() :: String.t()
  def passed_status, do: @passed_status

  @spec blocked_status() :: String.t()
  def blocked_status, do: @blocked_status

  @spec missing_status() :: String.t()
  def missing_status, do: @missing_status

  @spec failed_status() :: String.t()
  def failed_status, do: @failed_status

  @spec stale_status() :: String.t()
  def stale_status, do: @stale_status

  @spec complete_status() :: String.t()
  def complete_status, do: @complete_status

  @spec incomplete_status() :: String.t()
  def incomplete_status, do: @incomplete_status

  @spec unknown_status() :: String.t()
  def unknown_status, do: @unknown_status

  @spec unavailable_status() :: String.t()
  def unavailable_status, do: @unavailable_status

  @spec not_required_status() :: String.t()
  def not_required_status, do: @not_required_status

  @spec pending_status() :: String.t()
  def pending_status, do: @pending_status

  @spec linked_status() :: String.t()
  def linked_status, do: @linked_status

  @spec created_status() :: String.t()
  def created_status, do: @created_status

  @spec updated_status() :: String.t()
  def updated_status, do: @updated_status

  @spec clear_status() :: String.t()
  def clear_status, do: @clear_status

  @spec action_required_status() :: String.t()
  def action_required_status, do: @action_required_status

  @spec code_change_kind() :: String.t()
  def code_change_kind, do: @code_change_kind

  @spec no_code_change_kind() :: String.t()
  def no_code_change_kind, do: @no_code_change_kind

  @spec typed_tool_observed_source() :: String.t()
  def typed_tool_observed_source, do: @typed_tool_observed_source

  @spec tracker_observed_source() :: String.t()
  def tracker_observed_source, do: @tracker_observed_source

  @spec repo_observed_source() :: String.t()
  def repo_observed_source, do: @repo_observed_source

  @spec repo_provider_observed_source() :: String.t()
  def repo_provider_observed_source, do: @repo_provider_observed_source
end
