defmodule SymphonyElixir.Orchestrator.Retry.ResultSummary do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Retry.Status

  @retry_started "retry_started"
  @retry_cancelled "retry_cancelled"
  @retry_suppressed_non_dispatchable "retry_suppressed_non_dispatchable"
  @retry_suppressed_blocked "retry_suppressed_blocked"
  @continuation_scheduled "continuation_scheduled"
  @continuation_suppressed_non_dispatchable "continuation_suppressed_non_dispatchable"

  @spec retry_scheduled() :: String.t()
  def retry_scheduled, do: Status.retry_scheduled()

  @spec retry_started() :: String.t()
  def retry_started, do: @retry_started

  @spec retry_cancelled() :: String.t()
  def retry_cancelled, do: @retry_cancelled

  @spec retry_suppressed_non_dispatchable() :: String.t()
  def retry_suppressed_non_dispatchable, do: @retry_suppressed_non_dispatchable

  @spec retry_suppressed_blocked() :: String.t()
  def retry_suppressed_blocked, do: @retry_suppressed_blocked

  @spec continuation_scheduled() :: String.t()
  def continuation_scheduled, do: @continuation_scheduled

  @spec continuation_suppressed_non_dispatchable() :: String.t()
  def continuation_suppressed_non_dispatchable, do: @continuation_suppressed_non_dispatchable
end
