defmodule SymphonyElixir.Orchestrator.Retry.ResultSummary do
  @moduledoc false

  alias SymphonyElixir.Orchestrator.Retry.Status

  @retry_started "retry_started"
  @retry_cancelled "retry_cancelled"
  @continuation_scheduled "continuation_scheduled"

  @spec retry_scheduled() :: String.t()
  def retry_scheduled, do: Status.retry_scheduled()

  @spec retry_started() :: String.t()
  def retry_started, do: @retry_started

  @spec retry_cancelled() :: String.t()
  def retry_cancelled, do: @retry_cancelled

  @spec continuation_scheduled() :: String.t()
  def continuation_scheduled, do: @continuation_scheduled
end
